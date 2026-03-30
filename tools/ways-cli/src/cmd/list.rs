//! List ways triggered in the current session with epoch and disclosure state.
//! Shows conversation-ordered progression of way firings, epoch distances,
//! check fire counts, and predicted next-allowed-fire epochs.

use anyhow::Result;
use serde_json::json;
use std::collections::HashMap;

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

    // Assign pin symbols to re-disclosure clusters
    // Group ways by their bar position (re-disclosure point mapped to bar)
    let bar_width: usize = 60;
    let pin_symbols = ['●', '◆', '■', '▲', '◉', '▶', '★', '◈', '♦', '▪'];
    let pin_colors = [
        "\x1b[38;2;99;179;237m",  // blue
        "\x1b[38;2;78;205;196m",  // teal
        "\x1b[38;2;126;211;33m",  // green
        "\x1b[38;2;255;234;167m", // yellow
        "\x1b[38;2;253;203;110m", // orange
        "\x1b[38;2;255;118;117m", // red
        "\x1b[38;2;162;155;254m", // purple
        "\x1b[38;2;253;121;168m", // magenta
        "\x1b[38;2;116;185;255m", // sky
        "\x1b[38;2;85;239;196m",  // mint
    ];

    // Map each way to its bar position
    let way_bar_positions: Vec<Option<usize>> = ways
        .iter()
        .map(|w| {
            if context_window_k == 0 {
                return None;
            }
            let fire_pos_k = w.token_pos / 1000;
            let redisclose_at_k = fire_pos_k + redisclose_threshold_k;
            let bar_pos = ((redisclose_at_k * bar_width as u64) / context_window_k) as usize;
            Some(bar_pos.min(bar_width - 1))
        })
        .collect();

    // Assign a cluster index to each unique bar position
    let mut unique_positions: Vec<usize> = way_bar_positions
        .iter()
        .filter_map(|p| *p)
        .collect();
    unique_positions.sort();
    unique_positions.dedup();

    let cluster_of = |bar_pos: usize| -> usize {
        unique_positions.iter().position(|&p| p == bar_pos).unwrap_or(0) % pin_symbols.len()
    };

    // Column headers
    println!(
        "  \x1b[1m{:<34} {:>5} {:>5} {:<11} {} {}\x1b[0m",
        "Way", "Epoch", "Dist", "Trigger", "⌖", "Re-disclosure"
    );
    println!(
        "  \x1b[2m{}\x1b[0m",
        "─".repeat(85)
    );

    for (i, w) in ways.iter().enumerate() {
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

        // Color distance
        let dist_color = if distance == 0 {
            "\x1b[0;32m"
        } else if distance < current_epoch / 3 {
            "\x1b[0;32m"
        } else if distance < current_epoch * 2 / 3 {
            "\x1b[1;33m"
        } else {
            "\x1b[0;31m"
        };

        // Pin symbol for this way's re-disclosure cluster
        let pin = if let Some(bar_pos) = way_bar_positions[i] {
            let ci = cluster_of(bar_pos);
            format!("{}{}\x1b[0m", pin_colors[ci], pin_symbols[ci])
        } else {
            " ".to_string()
        };

        println!(
            "  {:<34} {:>5} {}{:>5}\x1b[0m {:<11} {} {}",
            truncate(&display_id, 34),
            w.epoch_at_fire,
            dist_color,
            distance,
            trigger_display,
            pin,
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

    // Token timeline with re-disclosure markers
    if current_tokens_k > 0 {
        println!();
        print_token_timeline(
            &ways,
            &way_bar_positions,
            &unique_positions,
            &pin_symbols,
            &pin_colors,
            current_tokens_k,
            context_window_k,
            redisclose_threshold_k,
        );
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
        return "\x1b[0;32m● now\x1b[0m".to_string();
    }
    if token_pct >= 75 {
        return format!("\x1b[1;33m◐ {token_pct}%\x1b[0m");
    }
    if token_pct >= 50 {
        return format!("\x1b[2m◔ {token_pct}%\x1b[0m");
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

// ── Token timeline ─────────────────────────────────────────────

fn print_token_timeline(
    ways: &[FiredWay],
    _way_bar_positions: &[Option<usize>],
    unique_positions: &[usize],
    pin_symbols: &[char],
    pin_colors: &[&str],
    current_tokens_k: u64,
    context_window_k: u64,
    redisclose_threshold_k: u64,
) {
    let bar_width: usize = 60;
    let pct = if context_window_k > 0 {
        (current_tokens_k * 100 / context_window_k).min(100)
    } else {
        0
    };
    let filled = (pct as usize * bar_width / 100).min(bar_width);

    // Collect re-disclosure points
    struct RdPoint {
        at_k: u64,
        cluster: usize,
        past: bool,
    }
    let mut points: Vec<RdPoint> = Vec::new();
    let mut zone_past = 0u32;
    let mut zone_soon = 0u32;
    let mut zone_later = 0u32;

    for w in ways {
        let fire_pos_k = w.token_pos / 1000;
        let redisclose_at_k = fire_pos_k + redisclose_threshold_k;
        let past = current_tokens_k >= redisclose_at_k;

        // Determine cluster index from the full-bar position (same as table pins)
        let full_bar_pos = if context_window_k > 0 {
            ((redisclose_at_k * bar_width as u64) / context_window_k) as usize
        } else {
            0
        }
        .min(bar_width - 1);

        let ci = unique_positions
            .iter()
            .position(|&p| p == full_bar_pos)
            .unwrap_or(0)
            % pin_symbols.len();

        points.push(RdPoint {
            at_k: redisclose_at_k,
            cluster: ci,
            past,
        });

        if past {
            zone_past += 1;
        } else {
            let dist = redisclose_at_k.saturating_sub(current_tokens_k);
            if dist <= redisclose_threshold_k / 4 {
                zone_soon += 1;
            } else {
                zone_later += 1;
            }
        }
    }

    // Usage bar (compact, full window)
    let bar_color = if pct < 50 {
        "\x1b[0;32m"
    } else if pct < 75 {
        "\x1b[1;33m"
    } else {
        "\x1b[0;31m"
    };

    let mut bar = String::new();
    for i in 0..bar_width {
        if i < filled {
            bar.push('█');
        } else {
            bar.push('░');
        }
    }
    println!(
        "  {bar_color}{bar}\x1b[0m {pct}% ({current_tokens_k}K / {context_window_k}K)"
    );

    // Forecast bar: zoomed view from current position to furthest re-disclosure
    let future_points: Vec<&RdPoint> = points.iter().filter(|p| !p.past).collect();

    if !future_points.is_empty() {
        let min_rd = future_points.iter().map(|p| p.at_k).min().unwrap_or(current_tokens_k);
        let max_rd = future_points.iter().map(|p| p.at_k).max().unwrap_or(context_window_k);

        // Zoom range: from current position to max re-disclosure + some padding
        let zoom_start = current_tokens_k;
        let zoom_end = (max_rd + (max_rd - min_rd) / 4).min(context_window_k); // pad 25%
        let zoom_span = zoom_end.saturating_sub(zoom_start).max(1);

        // Build zoomed marker line
        let mut zoom_markers: Vec<Option<usize>> = vec![None; bar_width];
        for p in &future_points {
            let offset = p.at_k.saturating_sub(zoom_start);
            let pos = ((offset * bar_width as u64) / zoom_span) as usize;
            let pos = pos.min(bar_width - 1);
            // Keep highest-priority cluster (lowest index wins for visibility)
            if zoom_markers[pos].is_none() {
                zoom_markers[pos] = Some(p.cluster);
            }
        }

        // Render zoomed forecast
        println!();
        println!(
            "  \x1b[1mForecast\x1b[0m \x1b[2m({zoom_start}K → {zoom_end}K)\x1b[0m"
        );

        // Marker line
        let mut marker_str = String::from("  ");
        for i in 0..bar_width {
            match zoom_markers[i] {
                Some(ci) => {
                    marker_str.push_str(&format!(
                        "{}{}\x1b[0m",
                        pin_colors[ci], pin_symbols[ci]
                    ));
                }
                None => marker_str.push('·'),
            }
        }
        println!("{marker_str}");

        // Scale labels
        let mid_k = zoom_start + zoom_span / 2;
        let mid_pos = bar_width / 2;
        let end_label = format!("{zoom_end}K");
        let end_pos = bar_width - end_label.len();
        let mut label_line = String::from("  ");
        let start_label = format!("{zoom_start}K");
        label_line.push_str(&format!("\x1b[2m{start_label}"));
        let pad1 = mid_pos.saturating_sub(start_label.len());
        label_line.push_str(&" ".repeat(pad1));
        let mid_label = format!("{mid_k}K");
        label_line.push_str(&mid_label);
        let pad2 = end_pos.saturating_sub(mid_pos + mid_label.len());
        label_line.push_str(&" ".repeat(pad2));
        label_line.push_str(&end_label);
        label_line.push_str("\x1b[0m");
        println!("{label_line}");
    }

    // Zone summary
    let mut zones = Vec::new();
    if zone_past > 0 {
        zones.push(format!("\x1b[0;32m● {zone_past} re-disclose now\x1b[0m"));
    }
    if zone_soon > 0 {
        zones.push(format!("\x1b[1;33m◐ {zone_soon} approaching\x1b[0m"));
    }
    if zone_later > 0 {
        zones.push(format!("\x1b[2m○ {zone_later} distant\x1b[0m"));
    }

    if !zones.is_empty() {
        println!(
            "  {}  \x1b[2m│ {redisclose_threshold_k}K interval\x1b[0m",
            zones.join("  ")
        );
    }
}

// ── Data collection ────────────────────────────────────────────

fn collect_fired_ways(session_id: &str, metrics: &HashMap<String, MetricEntry>) -> Vec<FiredWay> {
    // Way IDs are now real paths in the session directory — no parsing needed
    let way_epochs = session::list_way_epochs(session_id);

    way_epochs
        .into_iter()
        .map(|(way_id, epoch_at_fire)| {
            let token_pos = session::get_token_position_for_way(&way_id, session_id);
            let check_fires = session::get_check_fires(&way_id, session_id);

            let (trigger, depth, parent) = metrics
                .get(&way_id)
                .map(|m| (m.trigger.clone(), m.depth, m.parent.clone()))
                .unwrap_or_else(|| ("unknown".to_string(), 0, "none".to_string()));

            FiredWay {
                id: way_id,
                epoch_at_fire,
                token_pos,
                trigger,
                depth,
                check_fires,
                parent,
            }
        })
        .collect()
}

struct MetricEntry {
    trigger: String,
    depth: u64,
    parent: String,
}

fn load_metrics(session_id: &str) -> HashMap<String, MetricEntry> {
    let path = format!("/tmp/.claude-sessions/{session_id}/metrics.jsonl");
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
    // Find the session directory with the newest modification time
    let sessions = session::list_sessions();
    if sessions.is_empty() {
        return None;
    }
    if sessions.len() == 1 {
        return Some(sessions.into_iter().next().unwrap());
    }

    let mut newest: Option<(std::time::SystemTime, String)> = None;
    for sid in sessions {
        let dir = format!("/tmp/.claude-sessions/{sid}");
        if let Ok(meta) = std::fs::metadata(&dir) {
            let mtime = meta.modified().unwrap_or(std::time::UNIX_EPOCH);
            if newest.as_ref().map_or(true, |(t, _)| mtime > *t) {
                newest = Some((mtime, sid));
            }
        }
    }
    newest.map(|(_, s)| s)
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
