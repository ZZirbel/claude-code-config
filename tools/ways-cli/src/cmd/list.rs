//! List ways triggered in the current session with epoch and disclosure state.
//! Shows conversation-ordered progression of way firings, epoch distances,
//! check fire counts, and predicted next-allowed-fire epochs.

use anyhow::Result;
use serde_json::json;
use std::collections::HashMap;
use std::path::PathBuf;

use crate::cmd::context;
use crate::session;

/// A fired way with all its session state.
struct FiredWay {
    id: String,
    epoch_at_fire: u64,
    token_pos: u64,
    trigger: String,
    depth: u64,
    check_fires: u64,
    parent: String,
}

pub fn run(session: Option<&str>, sort: &str, json_out: bool) -> Result<()> {
    // Auto-detect session if not provided
    let session_id = match session {
        Some(s) => s.to_string(),
        None => match detect_session() {
            Some(s) => s,
            None => {
                println!("No session markers found. Ways will appear after the first hook fires.");
                return Ok(());
            }
        },
    };

    let current_epoch = session::get_epoch(&session_id);

    // Use accurate context data from transcript when available
    let (current_tokens_k, context_window_k) = match context::get_context(None) {
        Ok(ctx) => (ctx.tokens_used / 1000, ctx.tokens_total / 1000),
        Err(_) => {
            // Fallback to session markers
            let tok = session::get_token_position(&session_id) / 1000;
            (tok, if tok > 200 { 1000 } else { 200 })
        }
    };
    let redisclose_threshold_k = context_window_k * 25 / 100;

    // Collect metrics from JSONL (has trigger, depth, parent)
    let metrics = load_metrics(&session_id);

    // Collect all fired ways from markers
    let mut ways = collect_fired_ways(&session_id, &metrics);

    if ways.is_empty() {
        println!("No ways triggered yet this session.");
        return Ok(());
    }

    // Sort
    match sort {
        "name" => ways.sort_by(|a, b| a.id.cmp(&b.id)),
        "distance" => ways.sort_by(|a, b| {
            let da = current_epoch.saturating_sub(a.epoch_at_fire);
            let db = current_epoch.saturating_sub(b.epoch_at_fire);
            db.cmp(&da) // highest distance first
        }),
        _ => ways.sort_by_key(|w| w.epoch_at_fire), // epoch = conversation order
    }

    if json_out {
        print_json(&ways, current_epoch, current_tokens_k, context_window_k, redisclose_threshold_k);
        return Ok(());
    }

    // Header
    let short_id = &session_id[..session_id.len().min(12)];
    println!();
    println!(
        "\x1b[1mSession\x1b[0m {short_id}...  \x1b[2mepoch {current_epoch} · {context_window_k}K ctx · {} ways fired\x1b[0m",
        ways.len()
    );
    println!();

    // Column headers
    println!(
        "  \x1b[1m{:<34} {:>5} {:>5} {:<16} {}\x1b[0m",
        "Way", "Epoch", "Dist", "Trigger", "Next"
    );
    println!(
        "  \x1b[2m{}\x1b[0m",
        "─".repeat(82)
    );

    for w in &ways {
        let distance = current_epoch.saturating_sub(w.epoch_at_fire);
        let next = predict_next(&w, current_epoch, current_tokens_k, redisclose_threshold_k);

        // Indent children
        let prefix = if w.depth > 0 {
            format!("{}{}", "  ".repeat(w.depth as usize), "└ ")
        } else {
            String::new()
        };

        let display_id = format!("{prefix}{}", w.id);
        let trigger_display = format_trigger(&w.trigger);

        // Color distance: green (fresh) → yellow (mid) → red (stale)
        let dist_color = if distance == 0 {
            "\x1b[0;32m" // green
        } else if distance < current_epoch / 3 {
            "\x1b[0;32m"
        } else if distance < current_epoch * 2 / 3 {
            "\x1b[1;33m"
        } else {
            "\x1b[0;31m" // red
        };

        println!(
            "  {:<34} {:>5} {}{:>5}\x1b[0m {:<16} {}",
            truncate(&display_id, 34),
            w.epoch_at_fire,
            dist_color,
            distance,
            trigger_display,
            next,
        );

        // Show check fires if any
        if w.check_fires > 0 {
            let decay = 1.0 / (w.check_fires as f64 + 1.0);
            println!(
                "  \x1b[2m  ✓ check ({} fires, decay={:.2})\x1b[0m",
                w.check_fires, decay
            );
        }
    }

    // Token position bar
    if current_tokens_k > 0 {
        println!();
        print_token_bar(current_tokens_k, context_window_k);
    }

    println!();
    Ok(())
}

// ── Prediction ─────────────────────────────────────────────────

fn predict_next(w: &FiredWay, current_epoch: u64, current_tokens_k: u64, redisclose_threshold_k: u64) -> String {
    // Token-based re-disclosure: will this way re-fire due to context drift?
    let token_pos_k = w.token_pos / 1000;
    let token_distance_k = current_tokens_k.saturating_sub(token_pos_k);
    let token_pct = if redisclose_threshold_k > 0 {
        token_distance_k * 100 / redisclose_threshold_k
    } else {
        0
    };

    if token_pct >= 100 {
        return "\x1b[0;32m● re-disclose now\x1b[0m".to_string();
    }
    if token_pct >= 75 {
        return format!("\x1b[1;33m◐ {token_pct}% to re-disclose\x1b[0m");
    }
    if token_pct >= 50 {
        return format!("\x1b[2m◔ {token_pct}% to re-disclose\x1b[0m");
    }

    // Epoch-based: when would a check become relevant again?
    // check effective_score needs distance_factor × decay_factor to exceed threshold ~2.0
    // distance_factor = ln(distance + 1) + 1, so distance=6 → factor=2.95
    let epoch_distance = current_epoch.saturating_sub(w.epoch_at_fire);
    if w.check_fires > 0 {
        let decay = 1.0 / (w.check_fires as f64 + 1.0);
        // To fire at match_score=3: need 3 × distance_factor × decay ≥ 2.0
        // distance_factor ≥ 2/(3×decay) → ln(d+1)+1 ≥ that → solve for d
        let needed_factor = 2.0 / (3.0 * decay);
        let needed_distance = ((needed_factor - 1.0).exp() - 1.0).max(0.0) as u64;
        let next_epoch = w.epoch_at_fire + needed_distance;
        if epoch_distance < needed_distance {
            if needed_distance > 500 {
                return format!(
                    "\x1b[2mcheck ~{} (suppressed)\x1b[0m",
                    fmt_epoch(next_epoch)
                );
            }
            return format!("\x1b[2mcheck at epoch ~{next_epoch}\x1b[0m");
        }
    }

    "\x1b[2m─\x1b[0m".to_string()
}

// ── Token position bar ─────────────────────────────────────────

fn print_token_bar(current_tokens_k: u64, context_window_k: u64) {
    let pct = if context_window_k > 0 {
        (current_tokens_k * 100 / context_window_k).min(100)
    } else {
        0
    };

    let bar_width = 60;
    let filled = (pct as usize * bar_width / 100).min(bar_width);
    let empty = bar_width - filled;

    let bar_color = if pct < 50 {
        "\x1b[0;32m" // green
    } else if pct < 75 {
        "\x1b[1;33m" // yellow
    } else {
        "\x1b[0;31m" // red
    };

    // Mark the 25% re-disclosure zone
    let redisclose_pos = bar_width * 25 / 100;

    let mut bar = String::new();
    for i in 0..bar_width {
        if i < filled {
            bar.push('█');
        } else if i == redisclose_pos {
            bar.push('┊');
        } else {
            bar.push('░');
        }
    }

    println!(
        "  {bar_color}{bar}\x1b[0m {pct}% ({current_tokens_k}K / {context_window_k}K tokens)"
    );
    println!(
        "  \x1b[2m{}↑ 25% re-disclosure zone\x1b[0m",
        " ".repeat(redisclose_pos)
    );
}

// ── Data collection ────────────────────────────────────────────

fn collect_fired_ways(session_id: &str, metrics: &HashMap<String, MetricEntry>) -> Vec<FiredWay> {
    let pattern = format!("/tmp/.claude-way-epoch-*-{session_id}");
    let epoch_markers: Vec<PathBuf> = glob::glob(&pattern)
        .map(|paths| paths.filter_map(|p| p.ok()).collect())
        .unwrap_or_default();

    let mut ways = Vec::new();

    for marker in &epoch_markers {
        let name = marker.file_name().and_then(|n| n.to_str()).unwrap_or("");
        let name = name
            .strip_prefix(".claude-way-epoch-")
            .unwrap_or(name);

        // Strip session UUID from end: -{8hex}-{4hex}-{4hex}-{4hex}-{12hex}
        let way_name = match name.rfind(session_id) {
            Some(pos) => &name[..pos.saturating_sub(1)], // -1 for the leading dash
            None => continue,
        };
        let way_id = resolve_way_id(way_name);

        let epoch_at_fire = read_u64(&format!(
            "/tmp/.claude-way-epoch-{way_name}-{session_id}",
            way_name = way_name
        ));
        let token_pos = read_u64(&format!(
            "/tmp/.claude-way-tokens-{way_name}-{session_id}",
            way_name = way_name
        ));
        let check_fires = read_u64(&format!(
            "/tmp/.claude-check-fires-{way_name}-{session_id}",
            way_name = way_name
        ));

        let (trigger, depth, parent) = metrics
            .get(&way_id)
            .map(|m| (m.trigger.clone(), m.depth, m.parent.clone()))
            .unwrap_or_else(|| ("unknown".to_string(), 0, "none".to_string()));

        ways.push(FiredWay {
            id: way_id,
            epoch_at_fire,
            token_pos,
            trigger,
            depth,
            check_fires,
            parent,
        });
    }

    ways
}

struct MetricEntry {
    trigger: String,
    depth: u64,
    parent: String,
}

fn load_metrics(session_id: &str) -> HashMap<String, MetricEntry> {
    let path = format!("/tmp/.claude-way-metrics-{session_id}.jsonl");
    let content = match std::fs::read_to_string(&path) {
        Ok(c) => c,
        Err(_) => return HashMap::new(),
    };

    let mut map = HashMap::new();
    for line in content.lines() {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(line) {
            if let Some(way) = v["way"].as_str() {
                map.insert(
                    way.to_string(),
                    MetricEntry {
                        trigger: v["trigger"].as_str().unwrap_or("unknown").to_string(),
                        depth: v["depth"].as_u64().unwrap_or(0),
                        parent: v["parent"].as_str().unwrap_or("none").to_string(),
                    },
                );
            }
        }
    }
    map
}

fn detect_session() -> Option<String> {
    // Find the session with the newest epoch marker
    let mut newest: Option<(std::time::SystemTime, String)> = None;

    for entry in std::fs::read_dir("/tmp").ok()? {
        let entry = entry.ok()?;
        let name = entry.file_name();
        let name = name.to_string_lossy();
        if !name.starts_with(".claude-epoch-") {
            continue;
        }
        let sid = name.strip_prefix(".claude-epoch-")?.to_string();
        if let Ok(meta) = entry.metadata() {
            let mtime = meta.modified().unwrap_or(std::time::UNIX_EPOCH);
            if newest.as_ref().map_or(true, |(t, _)| mtime > *t) {
                newest = Some((mtime, sid));
            }
        }
    }

    newest.map(|(_, s)| s)
}

/// Resolve a dash-separated marker name to a way ID by testing against the filesystem.
/// e.g., "meta-knowledge-authoring-pii-free" → "meta/knowledge/authoring/pii-free"
/// Handles ambiguous cases like "adr-context" (sibling to "adr") by preferring
/// paths where every segment maps to an existing directory.
fn resolve_way_id(marker_name: &str) -> String {
    let ways_dir = std::env::var("HOME")
        .map(|h| PathBuf::from(h).join(".claude/hooks/ways"))
        .unwrap_or_else(|_| PathBuf::from("/tmp"));

    let parts: Vec<&str> = marker_name.split('-').collect();

    fn try_resolve(parts: &[&str], base: &std::path::Path) -> Option<String> {
        if parts.is_empty() {
            return None;
        }

        // Try split points from longest prefix to shortest.
        // For each, the segment must be an existing directory.
        // At the leaf (all parts consumed), the directory must exist.
        for i in (1..=parts.len()).rev() {
            let segment = parts[..i].join("-");
            let candidate = base.join(&segment);

            if !candidate.is_dir() {
                continue;
            }

            if i == parts.len() {
                // All parts consumed, directory exists — match
                return Some(segment);
            }

            // Recurse for remaining parts
            if let Some(rest) = try_resolve(&parts[i..], &candidate) {
                return Some(format!("{segment}/{rest}"));
            }
            // Recursion failed — this split doesn't lead to a valid full path.
            // Try a shorter prefix (the loop continues).
        }

        None
    }

    try_resolve(&parts, &ways_dir).unwrap_or_else(|| marker_name.replace('-', "/"))
}

fn fmt_epoch(n: u64) -> String {
    if n >= 1_000_000 {
        format!("{:.1e}", n as f64)
    } else if n >= 10_000 {
        format!("{}K", n / 1000)
    } else {
        format!("e{n}")
    }
}

fn format_trigger(trigger: &str) -> String {
    match trigger {
        "semantic:bm25" => "bm25".to_string(),
        "semantic:embedding" => "embed".to_string(),
        "keyword" => "keyword".to_string(),
        "check-pull" => "check-pull".to_string(),
        "bash" | "file" | "state" => trigger.to_string(),
        _ => trigger.to_string(),
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max - 1])
    }
}

fn read_u64(path: &str) -> u64 {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

fn print_json(ways: &[FiredWay], current_epoch: u64, current_tokens_k: u64, context_window_k: u64, redisclose_threshold_k: u64) {
    let entries: Vec<serde_json::Value> = ways
        .iter()
        .map(|w| {
            let distance = current_epoch.saturating_sub(w.epoch_at_fire);
            let token_pos_k = w.token_pos / 1000;
            let token_distance_k = current_tokens_k.saturating_sub(token_pos_k);
            let token_pct = if redisclose_threshold_k > 0 {
                token_distance_k * 100 / redisclose_threshold_k
            } else {
                0
            };
            json!({
                "id": w.id,
                "epoch_at_fire": w.epoch_at_fire,
                "epoch_distance": distance,
                "token_pos_k": token_pos_k,
                "token_distance_k": token_distance_k,
                "redisclose_pct": token_pct,
                "trigger": w.trigger,
                "depth": w.depth,
                "check_fires": w.check_fires,
                "parent": w.parent,
            })
        })
        .collect();

    let output = json!({
        "session": "current",
        "current_epoch": current_epoch,
        "current_tokens_k": current_tokens_k,
        "context_window_k": context_window_k,
        "ways_fired": entries.len(),
        "ways": entries,
    });

    println!("{}", serde_json::to_string_pretty(&output).unwrap_or_default());
}
