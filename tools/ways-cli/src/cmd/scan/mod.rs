//! Scan ways and output matched content — replaces hook scan loops.
//!
//! Combines file walking, frontmatter extraction, matching (pattern + semantic),
//! scope/precondition gating, parent-threshold lowering, and show (display).

mod candidates;
mod scoring;

use anyhow::Result;
use regex::Regex;
use std::path::PathBuf;

use crate::session;

use candidates::{check_when, collect_candidates, collect_checks};
use scoring::{
    batch_bm25_score, batch_embed_score, capture_show_check, capture_show_way, default_project,
};

pub(crate) struct WayCandidate {
    pub id: String,
    pub path: PathBuf,
    pub pattern: Option<String>,
    pub commands: Option<String>,
    pub files: Option<String>,
    pub description: String,
    pub vocabulary: String,
    pub threshold: f64,
    pub scope: String,
    pub when_project: Option<String>,
    pub when_file_exists: Option<String>,
    pub trigger: Option<String>,
    pub repeat: bool,
    pub trigger_path: Option<String>,
}

// ── Prompt scan ─────────────────────────────────────────────────

pub fn prompt(query: &str, session_id: &str, project: Option<&str>) -> Result<()> {
    let project_dir = project
        .map(|s| s.to_string())
        .unwrap_or_else(default_project);

    // Bump epoch
    session::bump_epoch(session_id);

    let scope = session::detect_scope(session_id);
    let candidates = collect_candidates(&project_dir);

    // Batch semantic scoring
    let bm25_matches = batch_bm25_score(query);
    let embed_matches = batch_embed_score(query);

    for way in &candidates {
        if !session::scope_matches(&way.scope, &scope) {
            continue;
        }
        if !check_when(&way.when_project, &way.when_file_exists, &project_dir) {
            continue;
        }

        // Parent-aware threshold lowering
        let effective_threshold = parent_threshold(&way.id, way.threshold, session_id);

        // Additive matching: pattern OR semantic
        let channel = match_prompt(
            query,
            &way.pattern,
            &way.id,
            effective_threshold,
            &bm25_matches,
            &embed_matches,
        );

        if let Some(trigger) = channel {
            let _ = crate::cmd::show::way(&way.id, session_id, &trigger);
        }
    }

    Ok(())
}

// ── Command scan ────────────────────────────────────────────────

pub fn command(
    cmd: &str,
    description: Option<&str>,
    session_id: &str,
    project: Option<&str>,
) -> Result<()> {
    let project_dir = project
        .map(|s| s.to_string())
        .unwrap_or_else(default_project);

    session::bump_epoch(session_id);
    let scope = session::detect_scope(session_id);
    let candidates = collect_candidates(&project_dir);

    let mut context = String::new();

    // Way matching: commands regex + pattern regex
    for way in &candidates {
        if !session::scope_matches(&way.scope, &scope) {
            continue;
        }
        if !check_when(&way.when_project, &way.when_file_exists, &project_dir) {
            continue;
        }

        let mut matched = false;

        if let Some(ref cmds_pattern) = way.commands {
            if regex_matches(cmds_pattern, cmd) {
                matched = true;
            }
        }

        if !matched {
            if let Some(ref desc) = description {
                if let Some(ref pat) = way.pattern {
                    if regex_matches(pat, &desc.to_lowercase()) {
                        matched = true;
                    }
                }
            }
        }

        if matched {
            let out = capture_show_way(&way.id, session_id, "bash");
            if !out.is_empty() {
                context.push_str(&out);
            }
        }
    }

    // Check matching: commands regex + semantic scoring
    let checks = collect_checks(&project_dir);
    let query_for_checks = format!(
        "{} {}",
        cmd,
        description.unwrap_or("")
    );

    // Batch BM25 for check scoring
    let bm25_matches = batch_bm25_score(&query_for_checks);

    for check in &checks {
        if !session::scope_matches(&check.scope, &scope) {
            continue;
        }
        if !check_when(&check.when_project, &check.when_file_exists, &project_dir) {
            continue;
        }

        let mut match_score: f64 = 0.0;

        if let Some(ref cmds_pattern) = check.commands {
            if regex_matches(cmds_pattern, cmd) {
                match_score = 3.0;
            }
        }

        if match_score == 0.0 && !check.description.is_empty() && !check.vocabulary.is_empty() {
            if let Some(score) = bm25_matches.iter().find(|(id, _)| *id == check.id).map(|(_, s)| *s) {
                if score > 0.0 {
                    match_score = score;
                }
            }
        }

        if match_score > 0.0 {
            let out = capture_show_check(&check.id, session_id, "bash", match_score);
            if !out.is_empty() {
                context.push_str(&out);
            }
        }
    }

    // Output JSON for PreToolUse
    if !context.is_empty() {
        println!(
            "{}",
            serde_json::json!({
                "decision": "approve",
                "additionalContext": context
            })
        );
    }

    Ok(())
}

// ── File scan ───────────────────────────────────────────────────

pub fn file(filepath: &str, session_id: &str, project: Option<&str>) -> Result<()> {
    let project_dir = project
        .map(|s| s.to_string())
        .unwrap_or_else(default_project);

    session::bump_epoch(session_id);
    let scope = session::detect_scope(session_id);
    let candidates = collect_candidates(&project_dir);

    let mut context = String::new();

    for way in &candidates {
        if !session::scope_matches(&way.scope, &scope) {
            continue;
        }
        if !check_when(&way.when_project, &way.when_file_exists, &project_dir) {
            continue;
        }

        if let Some(ref files_pattern) = way.files {
            if regex_matches(files_pattern, filepath) {
                let out = capture_show_way(&way.id, session_id, "file");
                if !out.is_empty() {
                    context.push_str(&out);
                }
            }
        }
    }

    // Check matching for files
    let checks = collect_checks(&project_dir);
    let bm25_matches = batch_bm25_score(filepath);

    for check in &checks {
        if !session::scope_matches(&check.scope, &scope) {
            continue;
        }
        if !check_when(&check.when_project, &check.when_file_exists, &project_dir) {
            continue;
        }

        let mut match_score: f64 = 0.0;

        if let Some(ref files_pattern) = check.files {
            if regex_matches(files_pattern, filepath) {
                match_score = 3.0;
            }
        }

        if match_score == 0.0 && !check.description.is_empty() && !check.vocabulary.is_empty() {
            if let Some(score) = bm25_matches.iter().find(|(id, _)| *id == check.id).map(|(_, s)| *s) {
                if score > 0.0 {
                    match_score = score;
                }
            }
        }

        if match_score > 0.0 {
            let out = capture_show_check(&check.id, session_id, "file", match_score);
            if !out.is_empty() {
                context.push_str(&out);
            }
        }
    }

    if !context.is_empty() {
        println!(
            "{}",
            serde_json::json!({
                "decision": "approve",
                "additionalContext": context
            })
        );
    }

    Ok(())
}

// ── Matching ────────────────────────────────────────────────────

fn match_prompt(
    query: &str,
    pattern: &Option<String>,
    way_id: &str,
    threshold: f64,
    bm25: &[(String, f64)],
    embed: &[(String, f64)],
) -> Option<String> {
    // Channel 1: Regex pattern — always checked first
    if let Some(ref pat) = pattern {
        if regex_matches(pat, query) {
            return Some("keyword".to_string());
        }
    }

    // Channel 2: Embedding — primary semantic engine when available.
    // If embed returned ANY results (engine is working), it's authoritative.
    // Only fall through to BM25 when embed returned nothing (engine unavailable).
    if !embed.is_empty() {
        if embed.iter().any(|(id, _)| id == way_id) {
            return Some("semantic:embedding".to_string());
        }
        // Embed is working but didn't match this way — don't fall through to BM25
        return None;
    }

    // Channel 3: BM25 — fallback when embedding engine is unavailable
    if let Some((_, score)) = bm25.iter().find(|(id, _)| id == way_id) {
        if *score >= threshold {
            return Some("semantic:bm25".to_string());
        }
    }

    None
}

fn parent_threshold(way_id: &str, threshold: f64, session_id: &str) -> f64 {
    let mut path = way_id.to_string();
    while let Some(idx) = path.rfind('/') {
        path = path[..idx].to_string();
        if session::way_is_shown(&path, session_id) {
            return threshold * 0.8;
        }
    }
    threshold
}

fn regex_matches(pattern: &str, text: &str) -> bool {
    Regex::new(pattern)
        .map(|re| re.is_match(text))
        .unwrap_or(false)
}

// ── State scan ──────────────────────────────────────────────────

pub fn state(
    session_id: &str,
    project: Option<&str>,
    transcript: Option<&str>,
) -> Result<()> {
    let project_dir = project
        .map(|s| s.to_string())
        .unwrap_or_else(default_project);

    let scope = session::detect_scope(session_id);
    let candidates = collect_candidates(&project_dir);

    let mut context = String::new();

    // Core re-injection safety net
    if !session::core_is_shown(session_id) {
        let out = capture_show_core(session_id);
        if !out.is_empty() {
            context.push_str(&out);
            context.push_str("\n\n");
        }
    } else if let Some(ref tp) = transcript {
        // Check for stale core (context cleared under us)
        let ctx_size = transcript_size_since_summary(tp);
        if let Some(marker_ts) = session::core_marker_ts(session_id) {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();
            let age = now.saturating_sub(marker_ts);
            if ctx_size < 5000 && age > 30 {
                session::clear_core(session_id);
                let out = capture_show_core(session_id);
                if !out.is_empty() {
                    context.push_str(&out);
                    context.push_str("\n\n");
                }
            }
        }
    }

    // State trigger evaluation
    for way in &candidates {
        let trigger_type = match &way.trigger {
            Some(t) => t.as_str(),
            None => continue,
        };

        if !session::scope_matches(&way.scope, &scope) {
            continue;
        }

        let triggered = match trigger_type {
            "context-threshold" => {
                evaluate_context_threshold(way.threshold as u64, transcript)
            }
            "file-exists" => {
                if let Some(ref pattern) = way.trigger_path {
                    evaluate_file_exists(pattern, &project_dir)
                } else {
                    false
                }
            }
            "session-start" => true,
            _ => false,
        };

        if !triggered {
            continue;
        }

        // Handle repeating context-threshold ways
        if trigger_type == "context-threshold" && way.repeat {
            let tasks_marker = format!("{}/{session_id}/tasks-active", crate::session::sessions_root());
            if std::path::Path::new(&tasks_marker).exists() {
                continue; // tasks active, suppress repeat
            }
            // Repeating: output body directly (no marker gating)
            let content = std::fs::read_to_string(&way.path).unwrap_or_default();
            let body = strip_frontmatter(&content);
            if !body.is_empty() {
                context.push_str(&body);
                context.push_str("\n\n");
                session::log_event(&[
                    ("event", "way_fired"),
                    ("way", &way.id),
                    ("domain", way.id.split('/').next().unwrap_or(&way.id)),
                    ("trigger", "state"),
                    ("scope", &scope),
                    ("project", &project_dir),
                    ("session", session_id),
                ]);
            }
        } else {
            // Standard one-shot: marker-gated via show
            let out = capture_show_way(&way.id, session_id, "state");
            if !out.is_empty() {
                context.push_str(&out);
                context.push_str("\n\n");
            }
        }
    }

    if !context.is_empty() {
        // Trim trailing newlines
        let trimmed = context.trim_end();
        println!(
            "{}",
            serde_json::json!({ "additionalContext": trimmed })
        );
    }

    Ok(())
}

fn evaluate_context_threshold(threshold_pct: u64, transcript: Option<&str>) -> bool {
    let transcript = match transcript {
        Some(t) if std::path::Path::new(t).is_file() => t,
        _ => return false,
    };

    // Detect model for context window size
    let window_chars: u64 = detect_window_chars(transcript);
    let limit = window_chars * threshold_pct / 100;
    let size = transcript_size_since_summary(transcript);

    size > limit
}

fn detect_window_chars(transcript: &str) -> u64 {
    let content = match std::fs::read_to_string(transcript) {
        Ok(c) => c,
        Err(_) => return 620_000,
    };
    for line in content.lines().rev() {
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(line) {
            if val.get("type").and_then(|t| t.as_str()) == Some("assistant") {
                if let Some(model) = val.get("message").and_then(|m| m.get("model")).and_then(|m| m.as_str()) {
                    if model.contains("opus-4") {
                        return 3_800_000;
                    }
                }
                break;
            }
        }
    }
    620_000 // default: ~155K tokens × 4 chars/token
}

fn transcript_size_since_summary(transcript: &str) -> u64 {
    let file_size = match std::fs::metadata(transcript) {
        Ok(m) => m.len(),
        Err(_) => return 0,
    };

    // Check last 100KB for summary markers
    let content = match std::fs::read_to_string(transcript) {
        Ok(c) => c,
        Err(_) => return file_size,
    };

    // Find last summary line position
    let mut last_summary_pos = 0u64;
    let mut pos = 0u64;
    for line in content.lines() {
        if line.contains("\"type\":\"summary\"") {
            last_summary_pos = pos + line.len() as u64 + 1;
        }
        pos += line.len() as u64 + 1;
    }

    file_size.saturating_sub(last_summary_pos)
}

fn evaluate_file_exists(pattern: &str, project_dir: &str) -> bool {
    // Use glob matching for patterns like "*.md" or ".claude/todo-*.md"
    let full_pattern = format!("{project_dir}/{pattern}");
    glob::glob(&full_pattern)
        .map(|paths| paths.filter_map(|p| p.ok()).next().is_some())
        .unwrap_or(false)
}

fn strip_frontmatter(content: &str) -> String {
    let mut fm_count = 0;
    let mut body = Vec::new();
    for line in content.lines() {
        if line == "---" {
            fm_count += 1;
            continue;
        }
        if fm_count >= 2 {
            body.push(line);
        }
    }
    body.join("\n")
}

fn capture_show_core(session_id: &str) -> String {
    crate::cmd::show::core(session_id).unwrap_or_default()
}
