//! Session state management — markers, epochs, token positions, scope detection.
//!
//! All session state lives in /tmp as flat files, scoped by session ID.
//! This module owns all reads and writes to those markers.

use std::path::{Path, PathBuf};

const MARKER_PREFIX: &str = "/tmp/.claude-way-";
const EPOCH_PREFIX: &str = "/tmp/.claude-epoch-";
const EPOCH_WAY_PREFIX: &str = "/tmp/.claude-way-epoch-";
const TOKEN_PREFIX: &str = "/tmp/.claude-way-tokens-";
const CHECK_FIRES_PREFIX: &str = "/tmp/.claude-check-fires-";
const CORE_PREFIX: &str = "/tmp/.claude-core-";
const TEAMMATE_PREFIX: &str = "/tmp/.claude-teammate-";
const METRICS_PREFIX: &str = "/tmp/.claude-way-metrics-";

/// Re-disclosure fires when a way has drifted this % of the context window.
const REDISCLOSE_PCT: u64 = 25;

// ── Marker names ────────────────────────────────────────────────

/// Sanitize a way ID for use in marker filenames (replace / with -).
pub fn marker_name(way_id: &str) -> String {
    way_id.replace('/', "-")
}

// ── Way markers ─────────────────────────────────────────────────

/// Check if a way has been shown this session.
pub fn way_is_shown(way_id: &str, session_id: &str) -> bool {
    marker_path(way_id, session_id).exists()
}

/// Write the way marker with the current token position.
pub fn stamp_way_marker(way_id: &str, session_id: &str, token_position: u64) {
    let path = marker_path(way_id, session_id);
    let _ = std::fs::write(&path, token_position.to_string());
}

fn marker_path(way_id: &str, session_id: &str) -> PathBuf {
    PathBuf::from(format!(
        "{}{}-{}",
        MARKER_PREFIX,
        marker_name(way_id),
        session_id
    ))
}

// ── Epochs ──────────────────────────────────────────────────────

/// Read the current epoch for a session.
pub fn get_epoch(session_id: &str) -> u64 {
    let path = format!("{}{}", EPOCH_PREFIX, session_id);
    read_u64(&path)
}

/// Bump the epoch counter, returning the new value.
pub fn bump_epoch(session_id: &str) -> u64 {
    let path = format!("{}{}", EPOCH_PREFIX, session_id);
    let next = read_u64(&path) + 1;
    let _ = std::fs::write(&path, next.to_string());
    next
}

/// Stamp when a way was last shown (epoch).
pub fn stamp_way_epoch(way_id: &str, session_id: &str, epoch: u64) {
    let name = marker_name(way_id);
    let path = format!("{}{}-{}", EPOCH_WAY_PREFIX, name, session_id);
    let _ = std::fs::write(&path, epoch.to_string());
}

/// Get the epoch when a way was last shown.
pub fn get_way_epoch(way_id: &str, session_id: &str) -> u64 {
    let name = marker_name(way_id);
    let path = format!("{}{}-{}", EPOCH_WAY_PREFIX, name, session_id);
    read_u64(&path)
}

/// Get epoch distance since a way last fired.
pub fn epoch_distance(way_id: &str, session_id: &str) -> u64 {
    let current = get_epoch(session_id);
    let way_ep = get_way_epoch(way_id, session_id);
    current.saturating_sub(way_ep)
}

// ── Token position (ADR-104 re-disclosure) ──────────────────────

/// Read the token position from the most recent transcript.
pub fn get_token_position(session_id: &str) -> u64 {
    let project_dir = std::env::var("CLAUDE_PROJECT_DIR")
        .unwrap_or_else(|_| std::env::var("PWD").unwrap_or_else(|_| ".".to_string()));
    let project_slug = project_dir.replace(['/', '.'], "-");
    let conv_dir = home_dir().join(format!(".claude/projects/{project_slug}"));

    // Find the most recent transcript JSONL
    let transcript = find_newest_jsonl(&conv_dir);
    let transcript = match transcript {
        Some(t) => t,
        None => return 0,
    };

    // Read the last assistant message's usage data
    let content = match std::fs::read_to_string(&transcript) {
        Ok(c) => c,
        Err(_) => return 0,
    };

    // Find the highest token count from assistant messages
    let mut max_tokens: u64 = 0;
    for line in content.lines().rev() {
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(line) {
            if val.get("type").and_then(|t| t.as_str()) == Some("assistant") {
                if let Some(usage) = val.get("message").and_then(|m| m.get("usage")) {
                    let cache_read = usage["cache_read_input_tokens"].as_u64().unwrap_or(0);
                    let cache_create = usage["cache_creation_input_tokens"].as_u64().unwrap_or(0);
                    let input = usage["input_tokens"].as_u64().unwrap_or(0);
                    let total = cache_read + cache_create + input;
                    if total > max_tokens {
                        max_tokens = total;
                    }
                    break; // Most recent is enough
                }
            }
        }
    }
    max_tokens
}

/// Stamp the token position when a way was last shown.
pub fn stamp_way_tokens(way_id: &str, session_id: &str, position: u64) {
    let name = marker_name(way_id);
    let path = format!("{}{}-{}", TOKEN_PREFIX, name, session_id);
    let _ = std::fs::write(&path, position.to_string());
}

/// Check if token distance exceeds re-disclosure threshold.
/// Returns Some(distance) if exceeded, None if not.
pub fn token_distance_exceeded(way_id: &str, session_id: &str) -> Option<u64> {
    let name = marker_name(way_id);
    let tokens_path = format!("{}{}-{}", TOKEN_PREFIX, name, session_id);
    let last_tokens = read_u64(&tokens_path);
    let current = get_token_position(session_id);
    let distance = current.saturating_sub(last_tokens);

    let context_window = detect_context_window(session_id);
    let threshold = context_window * REDISCLOSE_PCT / 100;

    if distance >= threshold {
        Some(distance)
    } else {
        None
    }
}

/// Detect context window size from the model in use.
fn detect_context_window(session_id: &str) -> u64 {
    let project_dir = std::env::var("CLAUDE_PROJECT_DIR")
        .unwrap_or_else(|_| std::env::var("PWD").unwrap_or_else(|_| ".".to_string()));
    let project_slug = project_dir.replace(['/', '.'], "-");
    let conv_dir = home_dir().join(format!(".claude/projects/{project_slug}"));

    let transcript = match find_newest_jsonl(&conv_dir) {
        Some(t) => t,
        None => return 200_000,
    };

    let content = match std::fs::read_to_string(&transcript) {
        Ok(c) => c,
        Err(_) => return 200_000,
    };

    // Find model name from last assistant message
    for line in content.lines().rev() {
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(line) {
            if val.get("type").and_then(|t| t.as_str()) == Some("assistant") {
                if let Some(model) = val.get("message").and_then(|m| m.get("model")).and_then(|m| m.as_str()) {
                    if model.contains("opus-4") {
                        return 1_000_000;
                    }
                }
                break;
            }
        }
    }
    200_000
}

// ── Check fire count ────────────────────────────────────────────

/// Get and increment fire count for a check.
pub fn bump_check_fires(way_id: &str, session_id: &str) -> u64 {
    let name = marker_name(way_id);
    let path = format!("{}{}-{}", CHECK_FIRES_PREFIX, name, session_id);
    let count = read_u64(&path) + 1;
    let _ = std::fs::write(&path, count.to_string());
    count
}

/// Get current fire count without incrementing.
pub fn get_check_fires(way_id: &str, session_id: &str) -> u64 {
    let name = marker_name(way_id);
    let path = format!("{}{}-{}", CHECK_FIRES_PREFIX, name, session_id);
    read_u64(&path)
}

// ── Core marker ─────────────────────────────────────────────────

pub fn stamp_core(session_id: &str) {
    let path = format!("{}{}", CORE_PREFIX, session_id);
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let _ = std::fs::write(&path, ts.to_string());
}

pub fn core_is_shown(session_id: &str) -> bool {
    Path::new(&format!("{}{}", CORE_PREFIX, session_id)).exists()
}

/// Read the timestamp from the core marker.
pub fn core_marker_ts(session_id: &str) -> Option<u64> {
    let path = format!("{}{}", CORE_PREFIX, session_id);
    std::fs::read_to_string(&path)
        .ok()
        .and_then(|s| s.trim().parse().ok())
}

/// Remove the core marker (for re-injection after context clear).
pub fn clear_core(session_id: &str) {
    let path = format!("{}{}", CORE_PREFIX, session_id);
    let _ = std::fs::remove_file(&path);
}

// ── Scope detection ─────────────────────────────────────────────

/// Detect execution scope: "agent" or "teammate".
pub fn detect_scope(session_id: &str) -> String {
    let path = format!("{}{}", TEAMMATE_PREFIX, session_id);
    if Path::new(&path).exists() {
        "teammate".to_string()
    } else {
        "agent".to_string()
    }
}

/// Read team name from teammate marker.
pub fn detect_team(session_id: &str) -> Option<String> {
    let path = format!("{}{}", TEAMMATE_PREFIX, session_id);
    std::fs::read_to_string(&path).ok().map(|s| s.trim().to_string())
}

/// Check if a way's scope field matches the current scope.
pub fn scope_matches(scope_field: &str, current_scope: &str) -> bool {
    if scope_field.is_empty() {
        return current_scope == "agent"; // default scope
    }
    scope_field.split(',').any(|s| s.trim() == current_scope)
}

// ── Metrics ─────────────────────────────────────────────────────

/// Append a tree disclosure metric.
pub fn append_metric(session_id: &str, metric: &serde_json::Value) {
    let path = format!("{}{}.jsonl", METRICS_PREFIX, session_id);
    if let Ok(line) = serde_json::to_string(metric) {
        let _ = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .and_then(|mut f| {
                use std::io::Write;
                writeln!(f, "{}", line)
            });
    }
}

// ── Event logging ───────────────────────────────────────────────

/// Log an event to ~/.claude/stats/events.jsonl.
pub fn log_event(fields: &[(&str, &str)]) {
    let stats_dir = home_dir().join(".claude/stats");
    let _ = std::fs::create_dir_all(&stats_dir);
    let events_file = stats_dir.join("events.jsonl");

    let ts = chrono_utc_now();
    let mut obj = serde_json::Map::new();
    obj.insert("ts".to_string(), serde_json::Value::String(ts));
    for (k, v) in fields {
        obj.insert(k.to_string(), serde_json::Value::String(v.to_string()));
    }

    if let Ok(line) = serde_json::to_string(&serde_json::Value::Object(obj)) {
        let _ = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&events_file)
            .and_then(|mut f| {
                use std::io::Write;
                writeln!(f, "{}", line)
            });
    }
}

/// UTC timestamp without chrono dependency.
fn chrono_utc_now() -> String {
    // Read /proc/uptime-based or fallback
    let secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    // Format as ISO 8601 — manual since we don't want a chrono dep
    let days_since_epoch = secs / 86400;
    let time_of_day = secs % 86400;
    let hours = time_of_day / 3600;
    let minutes = (time_of_day % 3600) / 60;
    let seconds = time_of_day % 60;

    // Approximate date from days since epoch (good enough for logging)
    let (year, month, day) = days_to_ymd(days_since_epoch);
    format!(
        "{year:04}-{month:02}-{day:02}T{hours:02}:{minutes:02}:{seconds:02}Z"
    )
}

/// Public wrapper for governance module.
pub fn days_to_ymd_pub(days: u64) -> (u64, u64, u64) {
    days_to_ymd(days)
}

fn days_to_ymd(days: u64) -> (u64, u64, u64) {
    // Simplified civil calendar conversion
    let z = days + 719468;
    let era = z / 146097;
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

// ── Domain disable check ────────────────────────────────────────

/// Check if a domain is disabled in ways.json.
pub fn domain_disabled(domain: &str) -> bool {
    let config = home_dir().join(".claude/ways.json");
    let content = match std::fs::read_to_string(&config) {
        Ok(c) => c,
        Err(_) => return false,
    };
    let parsed: serde_json::Value = match serde_json::from_str(&content) {
        Ok(v) => v,
        Err(_) => return false,
    };
    if let Some(disabled) = parsed.get("disabled").and_then(|v| v.as_array()) {
        return disabled.iter().any(|v| v.as_str() == Some(domain));
    }
    false
}

// ── Way file resolution ─────────────────────────────────────────

/// Resolve a way ID to its file path. Project-local takes precedence.
/// Returns (path, is_project_local).
pub fn resolve_way_file(way_id: &str, project_dir: &str) -> Option<(PathBuf, bool)> {
    // Project-local first
    let local_dir = PathBuf::from(project_dir).join(format!(".claude/ways/{way_id}"));
    if let Some(f) = find_way_in_dir(&local_dir) {
        return Some((f, true));
    }

    // Global
    let global_dir = home_dir().join(format!(".claude/hooks/ways/{way_id}"));
    if let Some(f) = find_way_in_dir(&global_dir) {
        return Some((f, false));
    }

    None
}

/// Resolve a way ID to its check file path.
pub fn resolve_check_file(way_id: &str, project_dir: &str) -> Option<(PathBuf, bool)> {
    let local_dir = PathBuf::from(project_dir).join(format!(".claude/ways/{way_id}"));
    if let Some(f) = find_check_in_dir(&local_dir) {
        return Some((f, true));
    }

    let global_dir = home_dir().join(format!(".claude/hooks/ways/{way_id}"));
    if let Some(f) = find_check_in_dir(&global_dir) {
        return Some((f, false));
    }

    None
}

fn find_way_in_dir(dir: &Path) -> Option<PathBuf> {
    if !dir.is_dir() {
        return None;
    }
    for entry in std::fs::read_dir(dir).ok()? {
        let entry = entry.ok()?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("md") {
            continue;
        }
        let name = path.file_name()?.to_str()?;
        if name.contains(".check.") {
            continue;
        }
        // Check for frontmatter
        if let Ok(content) = std::fs::read_to_string(&path) {
            if content.starts_with("---\n") {
                return Some(path);
            }
        }
    }
    None
}

fn find_check_in_dir(dir: &Path) -> Option<PathBuf> {
    if !dir.is_dir() {
        return None;
    }
    for entry in std::fs::read_dir(dir).ok()? {
        let entry = entry.ok()?;
        let path = entry.path();
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        if name.ends_with(".check.md") {
            return Some(path);
        }
    }
    None
}

// ── Helpers ─────────────────────────────────────────────────────

fn read_u64(path: &str) -> u64 {
    std::fs::read_to_string(path)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

fn find_newest_jsonl(dir: &Path) -> Option<PathBuf> {
    if !dir.is_dir() {
        return None;
    }
    let mut newest: Option<(std::time::SystemTime, PathBuf)> = None;
    for entry in std::fs::read_dir(dir).ok()? {
        let entry = entry.ok()?;
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) != Some("jsonl") {
            continue;
        }
        if path.to_str().map_or(false, |s| s.contains(".tmp")) {
            continue;
        }
        if let Ok(meta) = entry.metadata() {
            let mtime = meta.modified().unwrap_or(std::time::UNIX_EPOCH);
            if newest.as_ref().map_or(true, |(t, _)| mtime > *t) {
                newest = Some((mtime, path));
            }
        }
    }
    newest.map(|(_, p)| p)
}

fn home_dir() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}
