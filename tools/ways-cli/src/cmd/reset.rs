//! Reset session state — clear markers, epochs, and check fire counts.
//!
//! Unjams stale session state without restarting Claude Code.

use anyhow::Result;

use crate::session;


pub fn run(session: Option<&str>, all: bool, confirm: bool) -> Result<()> {
    let dry_run = !confirm;

    let sessions = if all {
        session::list_sessions()
    } else if let Some(sid) = session {
        vec![sid.to_string()]
    } else {
        let all_sessions = session::list_sessions();
        if all_sessions.is_empty() {
            println!("No session state found.");
            return Ok(());
        }
        if all_sessions.len() == 1 {
            all_sessions
        } else {
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
        println!("No session state found.");
        return Ok(());
    }

    let mut total = 0;

    for sid in &sessions {
        let dir = format!("{}/{sid}", session::sessions_root());
        let path = std::path::Path::new(&dir);
        if !path.is_dir() {
            continue;
        }

        let count = count_files(path);
        let short_id = &sid[..sid.len().min(12)];

        if dry_run {
            println!("Session {short_id}... ({count} state files)");
            // Show summary of what's in the directory
            let ways = session::list_fired_ways(sid);
            if !ways.is_empty() {
                println!("  ways: {}", ways.len());
            }
            let epoch = session::get_epoch(sid);
            if epoch > 0 {
                println!("  epoch: {epoch}");
            }
        } else {
            let _ = std::fs::remove_dir_all(path);
            println!("Session {short_id}...: cleared ({count} state files)");
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

fn count_files(dir: &std::path::Path) -> usize {
    walkdir::WalkDir::new(dir)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .count()
}

fn find_newest_session(sessions: &[String]) -> String {
    let mut newest = (std::time::UNIX_EPOCH, sessions[0].clone());

    for sid in sessions {
        let dir = format!("{}/{sid}", session::sessions_root());
        let path = std::path::Path::new(&dir);
        if let Ok(meta) = std::fs::metadata(path) {
            if let Ok(mtime) = meta.modified() {
                if mtime > newest.0 {
                    newest = (mtime, sid.clone());
                }
            }
        }
    }

    newest.1
}
