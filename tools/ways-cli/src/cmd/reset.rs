//! Reset session state — clear markers, epochs, and check fire counts.
//!
//! Unjams stale session state without restarting Claude Code.

use anyhow::Result;
use std::path::Path;

pub fn run(session: Option<&str>, all: bool, confirm: bool) -> Result<()> {
    let dry_run = !confirm;
    let sessions = if all {
        discover_sessions()
    } else if let Some(sid) = session {
        vec![sid.to_string()]
    } else {
        // Auto-detect: find sessions with markers in /tmp
        let all_sessions = discover_sessions();
        if all_sessions.is_empty() {
            println!("No session markers found in /tmp.");
            return Ok(());
        }
        if all_sessions.len() == 1 {
            all_sessions
        } else {
            // Multiple sessions — show them and pick the most recent
            let newest = find_newest_session(&all_sessions);
            eprintln!(
                "Found {} sessions, resetting newest: {}",
                all_sessions.len(),
                &newest[..newest.len().min(12)]
            );
            eprintln!("  (use --all to reset all, or --session <id> to target one)");
            vec![newest]
        }
    };

    if sessions.is_empty() {
        println!("No session markers found.");
        return Ok(());
    }

    let mut total = 0;

    for sid in &sessions {
        let files = find_markers(sid);
        if files.is_empty() {
            continue;
        }

        let short_id = &sid[..sid.len().min(12)];

        if dry_run {
            println!("Session {short_id}... ({} markers)", files.len());
            for f in &files {
                let name = Path::new(f)
                    .file_name()
                    .and_then(|n| n.to_str())
                    .unwrap_or(f);
                println!("  would remove: {name}");
            }
        } else {
            let count = files.len();
            for f in &files {
                let _ = std::fs::remove_file(f);
            }
            println!("Session {short_id}...: cleared {count} markers");
            total += count;
        }
    }

    if dry_run {
        println!();
        println!("\x1b[1;33mDry run\x1b[0m — no files removed. Add \x1b[1m--confirm\x1b[0m to execute.");
        println!();
        println!("\x1b[2mNote: resetting mid-session causes all ways to re-fire on the next");
        println!("hook invocation. Core guidance, checks, and progressive disclosure");
        println!("state will restart from scratch. This is safe but noisy — best used");
        println!("when the session feels jammed or after significant context shifts.\x1b[0m");
    } else if total > 0 {
        println!("\nReset complete. Ways will re-disclose on next hook invocation.");
    } else {
        println!("Nothing to clear.");
    }

    Ok(())
}

/// Find all unique session IDs from /tmp/.claude-* markers.
fn discover_sessions() -> Vec<String> {
    let mut sessions = std::collections::HashSet::new();

    if let Ok(entries) = std::fs::read_dir("/tmp") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if !name.starts_with(".claude-") {
                continue;
            }
            // Extract session ID: it's the UUID at the end
            // Pattern: .claude-{type}-{way-name}-{uuid}
            // or: .claude-{type}-{uuid}
            if let Some(sid) = extract_session_id(&name) {
                sessions.insert(sid);
            }
        }
    }

    let mut sorted: Vec<String> = sessions.into_iter().collect();
    sorted.sort();
    sorted
}

/// Extract a UUID-shaped session ID from a marker filename.
fn extract_session_id(name: &str) -> Option<String> {
    // Session IDs look like: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    // or sim-s1-12345 (test sessions)
    // Find the last segment that looks like a UUID or test ID
    let parts: Vec<&str> = name.split('-').collect();
    if parts.len() < 6 {
        return None;
    }

    // Try to find a UUID pattern (8-4-4-4-12)
    for window in parts.windows(5) {
        if window[0].len() == 8
            && window[1].len() == 4
            && window[2].len() == 4
            && window[3].len() == 4
            && window[4].len() == 12
            && window.iter().all(|p| p.chars().all(|c| c.is_ascii_hexdigit()))
        {
            return Some(format!(
                "{}-{}-{}-{}-{}",
                window[0], window[1], window[2], window[3], window[4]
            ));
        }
    }

    // Fallback for test sessions (sim-s1-12345)
    if name.contains("sim-") {
        let rest = name.rsplit_once("sim-").map(|(_, r)| r)?;
        let sid = format!("sim-{}", rest.split('-').take(2).collect::<Vec<_>>().join("-"));
        return Some(sid);
    }

    None
}

/// Find all /tmp/.claude-* files matching a session ID.
fn find_markers(session_id: &str) -> Vec<String> {
    let mut files = Vec::new();
    if let Ok(entries) = std::fs::read_dir("/tmp") {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if name.starts_with(".claude-") && name.ends_with(session_id) {
                files.push(entry.path().to_string_lossy().to_string());
            }
        }
    }
    files.sort();
    files
}

/// Pick the session with the newest marker (by mtime).
fn find_newest_session(sessions: &[String]) -> String {
    let mut newest = (std::time::UNIX_EPOCH, sessions[0].clone());

    for sid in sessions {
        let markers = find_markers(sid);
        for path in &markers {
            if let Ok(meta) = std::fs::metadata(path) {
                if let Ok(mtime) = meta.modified() {
                    if mtime > newest.0 {
                        newest = (mtime, sid.clone());
                    }
                }
            }
        }
    }

    newest.1
}
