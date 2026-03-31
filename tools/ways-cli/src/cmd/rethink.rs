//! Interactive session replay — animate `ways list` state across a session's history.
//!
//! Reconstructs the progressive disclosure timeline from events.jsonl,
//! building cumulative frames at each epoch. Renders each frame using
//! the same visual format as `ways list`, with interactive controls.

#[cfg(feature = "tui")]
use crossterm::{
    cursor,
    event::{self, Event, KeyCode, KeyEvent, KeyModifiers},
    execute,
    terminal::{self, ClearType},
};

use anyhow::Result;
use std::collections::HashMap;
use std::fmt::Write as FmtWrite;
use std::io::Write;

use crate::util::{detect_project_dir, home_dir};

// ── Data structures ───────────────────────────────────────────

/// A way event from events.jsonl.
struct WayEvent {
    ts: String,
    event: String,
    way: String,
    trigger: String,
    #[allow(dead_code)]
    scope: String,
    check: String,
    #[allow(dead_code)]
    token_position: u64,
}

/// An active way at a given frame.
#[derive(Clone)]
struct ActiveWay {
    id: String,
    trigger: String,
    epoch_fired: u64,
    token_pos: u64,
    check_fires: u64,
    is_new: bool,
    is_redisclosed: bool,
}

/// A single frame in the replay.
struct Frame {
    epoch: u64,
    timestamp: String,
    elapsed_secs: u64,
    token_position_k: u64,
    ways: Vec<ActiveWay>,
    new_events: Vec<String>, // human-readable summary of what happened this frame
}

/// Playback state.
struct Player {
    frames: Vec<Frame>,
    current: usize,
    playing: bool,
    speed_idx: usize,
    session_id: String,
    #[allow(dead_code)]
    project: String,
    context_window_k: u64,
    term_width: u16,
    term_height: u16,
}

const SPEEDS: &[(u64, &str)] = &[
    (2000, "2.0s"),
    (1000, "1.0s"),
    (500, "0.5s"),
    (250, "0.25s"),
    (100, "0.1s"),
];

// ── Entry point ───────────────────────────────────────────────

#[cfg(feature = "tui")]
pub fn run(session: Option<&str>, project: Option<&str>, speed: Option<u64>, list: bool) -> Result<()> {
    let events_file = home_dir().join(".claude/stats/events.jsonl");
    if !events_file.is_file() {
        println!("No events recorded yet.");
        return Ok(());
    }

    let content = std::fs::read_to_string(&events_file)?;

    // Auto-detect project scope if not explicitly provided
    let detected_project = if project.is_none() {
        std::env::var("CLAUDE_PROJECT_DIR")
            .ok()
            .or_else(detect_project_dir)
    } else {
        None
    };
    let project_scope = project.map(|s| s.to_string()).or(detected_project);

    if list {
        return list_sessions(&content, project_scope.as_deref());
    }

    // Find the session: explicit > interactive picker > latest fallback
    let session_id = match session {
        Some(s) => s.to_string(),
        None => {
            // Try interactive picker, scoped to current project
            match pick_session(&content, project_scope.as_deref()) {
                Some(s) => s,
                None => return Ok(()), // user pressed Esc
            }
        }
    };

    let project_name = find_session_project(&content, &session_id)
        .unwrap_or_else(|| "unknown".to_string());

    // Load and build frames
    let events = load_session_events(&content, &session_id);
    if events.is_empty() {
        println!("No events found for session {}", &session_id[..session_id.len().min(12)]);
        return Ok(());
    }

    let context_window_k = detect_context_window_for_session(&project_name, &session_id);
    let token_timeline = build_token_timeline(&project_name, &session_id);
    let frames = build_frames(&events, &token_timeline);

    if frames.is_empty() {
        println!("No frames to replay.");
        return Ok(());
    }

    let speed_idx = match speed {
        Some(ms) => SPEEDS.iter().position(|(s, _)| *s <= ms).unwrap_or(1),
        None => 1, // default 1.0s
    };

    let (term_width, term_height) = terminal::size().unwrap_or((120, 40));

    let mut player = Player {
        frames,
        current: 0,
        playing: false,
        speed_idx,
        session_id,
        project: project_name,
        context_window_k,
        term_width,
        term_height,
    };

    run_tui(&mut player)
}

#[cfg(not(feature = "tui"))]
pub fn run(_session: Option<&str>, _project: Option<&str>, _speed: Option<u64>, list: bool) -> Result<()> {
    if list {
        let events_file = home_dir().join(".claude/stats/events.jsonl");
        if !events_file.is_file() {
            println!("No events recorded yet.");
            return Ok(());
        }
        let content = std::fs::read_to_string(&events_file)?;
        return list_sessions(&content, None);
    }
    println!("Rethink requires the 'tui' feature. Build with: cargo build --features tui");
    Ok(())
}

// ── TUI loop ──────────────────────────────────────────────────

#[cfg(feature = "tui")]
fn run_tui(player: &mut Player) -> Result<()> {
    let mut stdout = std::io::stdout();

    terminal::enable_raw_mode()?;
    execute!(stdout, terminal::EnterAlternateScreen, cursor::Hide)?;

    let result = tui_loop(player, &mut stdout);

    execute!(stdout, cursor::Show, terminal::LeaveAlternateScreen)?;
    terminal::disable_raw_mode()?;

    result
}

#[cfg(feature = "tui")]
fn tui_loop(player: &mut Player, stdout: &mut std::io::Stdout) -> Result<()> {
    loop {
        // Refresh terminal size on each frame (handles resizes)
        if let Ok((w, h)) = terminal::size() {
            player.term_width = w;
            player.term_height = h;
        }

        // Render current frame, truncate lines to terminal width
        let raw_output = render_frame(player);
        let output = fit_to_terminal(&raw_output, player.term_width as usize, player.term_height as usize);
        execute!(stdout, cursor::MoveTo(0, 0), terminal::Clear(ClearType::All))?;
        write!(stdout, "{output}")?;
        stdout.flush()?;

        // Input handling
        let timeout = if player.playing {
            std::time::Duration::from_millis(SPEEDS[player.speed_idx].0)
        } else {
            std::time::Duration::from_secs(60) // block in paused mode
        };

        if event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                match key {
                    KeyEvent { code: KeyCode::Esc, .. }
                    | KeyEvent { code: KeyCode::Char('q'), .. } => break,

                    // Ctrl+C
                    KeyEvent { code: KeyCode::Char('c'), modifiers: KeyModifiers::CONTROL, .. } => break,

                    KeyEvent { code: KeyCode::Right, .. }
                    | KeyEvent { code: KeyCode::Char('l'), .. } => {
                        player.playing = false;
                        if player.current < player.frames.len() - 1 {
                            player.current += 1;
                        }
                    }

                    KeyEvent { code: KeyCode::Left, .. }
                    | KeyEvent { code: KeyCode::Char('h'), .. } => {
                        player.playing = false;
                        if player.current > 0 {
                            player.current -= 1;
                        }
                    }

                    KeyEvent { code: KeyCode::Char(' '), .. } => {
                        player.playing = !player.playing;
                    }

                    KeyEvent { code: KeyCode::Up, .. }
                    | KeyEvent { code: KeyCode::Char('k'), .. } => {
                        if player.speed_idx < SPEEDS.len() - 1 {
                            player.speed_idx += 1;
                        }
                    }

                    KeyEvent { code: KeyCode::Down, .. }
                    | KeyEvent { code: KeyCode::Char('j'), .. } => {
                        if player.speed_idx > 0 {
                            player.speed_idx -= 1;
                        }
                    }

                    KeyEvent { code: KeyCode::Home, .. }
                    | KeyEvent { code: KeyCode::Char('g'), .. } => {
                        player.current = 0;
                        player.playing = false;
                    }

                    KeyEvent { code: KeyCode::End, .. }
                    | KeyEvent { code: KeyCode::Char('G'), .. } => {
                        player.current = player.frames.len() - 1;
                        player.playing = false;
                    }

                    _ => {}
                }
            }
        } else if player.playing {
            // Autoplay: advance frame
            if player.current < player.frames.len() - 1 {
                player.current += 1;
            } else {
                player.playing = false; // stop at end
            }
        }
    }
    Ok(())
}

// ── Frame renderer ────────────────────────────────────────────

fn render_frame(player: &Player) -> String {
    let frame = &player.frames[player.current];
    let current_epoch = frame.epoch;
    let context_window_k = player.context_window_k;
    let current_tokens_k = frame.token_position_k;
    let redisclose_threshold_k = context_window_k * 25 / 100;

    let mut out = String::new();

    // Header
    let short_id = &player.session_id[..player.session_id.len().min(12)];
    let _ = writeln!(out);
    let _ = writeln!(
        out,
        "\x1b[1mSession\x1b[0m {short_id}...  \x1b[2mepoch {current_epoch} · {context_window_k}K ctx · {} ways fired\x1b[0m",
        frame.ways.len()
    );

    // Timestamp and elapsed
    let _ = writeln!(
        out,
        "\x1b[2m  {} · +{}s elapsed\x1b[0m",
        &frame.timestamp[..frame.timestamp.len().min(19)],
        frame.elapsed_secs
    );
    let _ = writeln!(out);

    if frame.ways.is_empty() {
        let _ = writeln!(out, "  \x1b[2mNo ways triggered yet.\x1b[0m");
        let _ = writeln!(out);
        render_status_bar(&mut out, player);
        return out;
    }

    // Pin symbols and colors (same as list.rs)
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
    let way_bar_positions: Vec<Option<usize>> = frame
        .ways
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
    let _ = writeln!(
        out,
        "  \x1b[1m{:<34} {:>5} {:>5} {:<11} {} {}\x1b[0m",
        "Way", "Epoch", "Dist", "Trigger", "⌖", "Re-disclosure"
    );
    let _ = writeln!(out, "  \x1b[2m{}\x1b[0m", "─".repeat(85));

    for (i, w) in frame.ways.iter().enumerate() {
        let distance = current_epoch.saturating_sub(w.epoch_fired);

        // Highlight newly-fired ways
        let row_prefix = if w.is_new {
            "\x1b[1;32m"
        } else if w.is_redisclosed {
            "\x1b[1;36m"
        } else {
            ""
        };
        let row_suffix = if w.is_new || w.is_redisclosed { "\x1b[0m" } else { "" };

        let next = predict_next(w, current_epoch, current_tokens_k, redisclose_threshold_k);

        let trigger_display = format_trigger(&w.trigger);

        // Color distance
        let dist_color = if distance == 0 {
            "\x1b[0;32m"
        } else if current_epoch > 0 && distance < current_epoch / 3 {
            "\x1b[0;32m"
        } else if current_epoch > 0 && distance < current_epoch * 2 / 3 {
            "\x1b[1;33m"
        } else {
            "\x1b[0;31m"
        };

        let pin = if let Some(bar_pos) = way_bar_positions[i] {
            let ci = cluster_of(bar_pos);
            format!("{}{}\x1b[0m", pin_colors[ci], pin_symbols[ci])
        } else {
            " ".to_string()
        };

        let _ = writeln!(
            out,
            "  {row_prefix}{:<34} {:>5} {}{:>5}\x1b[0m {:<11} {} {}{row_suffix}",
            truncate(&w.id, 34),
            w.epoch_fired,
            dist_color,
            distance,
            trigger_display,
            pin,
            next,
        );

        if w.check_fires > 0 {
            let decay = 1.0 / (w.check_fires as f64 + 1.0);
            let _ = writeln!(
                out,
                "  \x1b[2m  ✓ check ({} fires, decay={:.2})\x1b[0m",
                w.check_fires, decay
            );
        }
    }

    // Token timeline
    if current_tokens_k > 0 {
        let _ = writeln!(out);
        render_token_timeline(
            &mut out,
            &frame.ways,
            &way_bar_positions,
            &unique_positions,
            &pin_symbols,
            &pin_colors,
            current_tokens_k,
            context_window_k,
            redisclose_threshold_k,
        );
    }

    let _ = writeln!(out);

    // New events this frame
    if !frame.new_events.is_empty() {
        let _ = writeln!(out, "  \x1b[1;32m+ {}\x1b[0m", frame.new_events.join(", "));
        let _ = writeln!(out);
    }

    // Status bar at bottom
    render_status_bar(&mut out, player);

    out
}

fn render_status_bar(out: &mut String, player: &Player) {
    let total = player.frames.len();
    let current = player.current + 1;
    let speed_label = SPEEDS[player.speed_idx].1;
    let state = if player.playing { "▶ playing" } else { "⏸ paused" };

    let _ = write!(
        out,
        "\x1b[2m{}\x1b[0m\n",
        "─".repeat(85)
    );
    let _ = write!(
        out,
        " \x1b[7m ◀ ▶ \x1b[0m frame  \
         \x1b[7m ⏵ \x1b[0m play/pause  \
         \x1b[7m ▲▼ \x1b[0m speed  \
         \x1b[7m esc \x1b[0m quit  \
         \x1b[2m│\x1b[0m  \
         \x1b[1m{current}/{total}\x1b[0m  \
         {speed_label}  \
         {state}"
    );
}

fn render_token_timeline(
    out: &mut String,
    ways: &[ActiveWay],
    _way_bar_positions: &[Option<usize>],
    unique_positions: &[usize],
    pin_symbols: &[char; 10],
    pin_colors: &[&str; 10],
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

    let future_points: Vec<&RdPoint> = points.iter().filter(|p| !p.past).collect();

    let (zoom_start, zoom_end, zoom_span) = if !future_points.is_empty() {
        let min_rd = future_points.iter().map(|p| p.at_k).min().unwrap_or(current_tokens_k);
        let max_rd = future_points.iter().map(|p| p.at_k).max().unwrap_or(context_window_k);
        let zs = current_tokens_k;
        let ze = (max_rd + (max_rd - min_rd) / 4).min(context_window_k);
        (zs, ze, ze.saturating_sub(zs).max(1))
    } else {
        (0, 0, 0)
    };

    let bar_color = if pct < 50 {
        "\x1b[0;32m"
    } else if pct < 75 {
        "\x1b[1;33m"
    } else {
        "\x1b[0;31m"
    };

    let zoom_bar_start = if context_window_k > 0 && zoom_span > 0 {
        ((zoom_start * bar_width as u64) / context_window_k) as usize
    } else {
        0
    };
    let zoom_bar_end = if context_window_k > 0 && zoom_span > 0 {
        ((zoom_end * bar_width as u64) / context_window_k) as usize
    } else {
        0
    }
    .min(bar_width.saturating_sub(1));

    let mut bar = String::new();
    for i in 0..bar_width {
        if i < filled {
            bar.push('█');
        } else {
            bar.push('░');
        }
    }
    let _ = writeln!(
        out,
        "  {bar_color}{bar}\x1b[0m {pct}% ({current_tokens_k}K / {context_window_k}K)"
    );

    if zoom_span > 0 {
        let mut arrow_line = String::from("  ");
        for i in 0..bar_width {
            if i == zoom_bar_start || i == zoom_bar_end {
                arrow_line.push('^');
            } else {
                arrow_line.push(' ');
            }
        }
        let _ = writeln!(out, "\x1b[2m{arrow_line}\x1b[0m");
    }

    if !future_points.is_empty() {
        let mut zoom_markers: Vec<Option<usize>> = vec![None; bar_width];
        for p in &future_points {
            let offset = p.at_k.saturating_sub(zoom_start);
            let pos = ((offset * bar_width as u64) / zoom_span) as usize;
            let pos = pos.min(bar_width - 1);
            if zoom_markers[pos].is_none() {
                zoom_markers[pos] = Some(p.cluster);
            }
        }

        let _ = writeln!(out);
        let _ = writeln!(
            out,
            "  \x1b[1mForecast\x1b[0m \x1b[2m({zoom_start}K → {zoom_end}K)\x1b[0m"
        );

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
        let _ = writeln!(out, "{marker_str}");

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
        let _ = writeln!(out, "{label_line}");
    }

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
        let _ = writeln!(
            out,
            "  {}  \x1b[2m│ {redisclose_threshold_k}K interval\x1b[0m",
            zones.join("  ")
        );
    }
}

// ── Frame construction ────────────────────────────────────────

fn build_frames(events: &[WayEvent], token_timeline: &[(String, u64)]) -> Vec<Frame> {
    let mut frames: Vec<Frame> = Vec::new();
    let mut active_ways: HashMap<String, ActiveWay> = HashMap::new();
    let mut check_fires: HashMap<String, u64> = HashMap::new();
    let mut epoch: u64 = 0;

    let start_ts = events.first().map(|e| &e.ts).cloned().unwrap_or_default();
    let start_secs = parse_ts_secs(&start_ts);

    // Cluster events by timestamp proximity (≤3s gap = same epoch)
    let mut clusters: Vec<Vec<&WayEvent>> = Vec::new();
    let mut current_cluster: Vec<&WayEvent> = Vec::new();
    let mut last_ts_secs: u64 = 0;

    for ev in events {
        let ts_secs = parse_ts_secs(&ev.ts);
        if !current_cluster.is_empty() && ts_secs > last_ts_secs + 3 {
            clusters.push(std::mem::take(&mut current_cluster));
        }
        current_cluster.push(ev);
        last_ts_secs = ts_secs;
    }
    if !current_cluster.is_empty() {
        clusters.push(current_cluster);
    }

    for cluster in &clusters {
        epoch += 1;
        let cluster_ts = cluster[0].ts.clone();
        let cluster_secs = parse_ts_secs(&cluster_ts);
        let elapsed = cluster_secs.saturating_sub(start_secs);

        // Find best token position from timeline at or before this timestamp
        let token_k = find_token_position(token_timeline, &cluster_ts);

        let mut new_events: Vec<String> = Vec::new();

        // Mark all existing ways as not-new
        for w in active_ways.values_mut() {
            w.is_new = false;
            w.is_redisclosed = false;
        }

        for ev in cluster {
            match ev.event.as_str() {
                "way_fired" => {
                    if !ev.way.is_empty() {
                        let existing = active_ways.get(&ev.way);
                        if existing.is_none() {
                            new_events.push(format!("{} ({})", ev.way, format_trigger(&ev.trigger)));
                        }
                        active_ways.insert(ev.way.clone(), ActiveWay {
                            id: ev.way.clone(),
                            trigger: ev.trigger.clone(),
                            epoch_fired: epoch,
                            token_pos: token_k * 1000,
                            check_fires: check_fires.get(&ev.way).copied().unwrap_or(0),
                            is_new: existing.is_none(),
                            is_redisclosed: false,
                        });
                    }
                }
                "check_fired" => {
                    if !ev.check.is_empty() {
                        let count = check_fires.entry(ev.check.clone()).or_insert(0);
                        *count += 1;
                        if let Some(w) = active_ways.get_mut(&ev.check) {
                            w.check_fires = *count;
                        }
                        new_events.push(format!("✓ check {}", ev.check));
                    }
                }
                "way_redisclosed" => {
                    if !ev.way.is_empty() {
                        new_events.push(format!("↻ {}", ev.way));
                        active_ways.entry(ev.way.clone()).and_modify(|w| {
                            w.epoch_fired = epoch;
                            w.token_pos = token_k * 1000;
                            w.is_redisclosed = true;
                            w.is_new = false;
                        });
                    }
                }
                _ => {}
            }
        }

        // Build sorted ways list for this frame
        let mut ways: Vec<ActiveWay> = active_ways.values().cloned().collect();
        ways.sort_by_key(|w| w.epoch_fired);

        frames.push(Frame {
            epoch,
            timestamp: cluster_ts,
            elapsed_secs: elapsed,
            token_position_k: token_k,
            ways,
            new_events,
        });
    }

    frames
}

fn build_token_timeline(project: &str, session_id: &str) -> Vec<(String, u64)> {
    let project_slug = project.replace(['/', '.'], "-");
    let transcript_path = home_dir()
        .join(format!(".claude/projects/{project_slug}/{session_id}.jsonl"));

    let content = match std::fs::read_to_string(&transcript_path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    let mut timeline: Vec<(String, u64)> = Vec::new();

    for line in content.lines() {
        if !line.contains("cache_read_input_tokens") {
            continue;
        }
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(line) {
            if val.get("type").and_then(|t| t.as_str()) != Some("assistant") {
                continue;
            }
            let ts = val.get("timestamp")
                .and_then(|t| t.as_str())
                .unwrap_or("")
                .to_string();

            if let Some(usage) = val.get("message").and_then(|m| m.get("usage")) {
                let cache_read = usage["cache_read_input_tokens"].as_u64().unwrap_or(0);
                let cache_create = usage["cache_creation_input_tokens"].as_u64().unwrap_or(0);
                let input = usage["input_tokens"].as_u64().unwrap_or(0);
                let total_k = (cache_read + cache_create + input) / 1000;
                if !ts.is_empty() {
                    timeline.push((ts, total_k));
                }
            }
        }
    }

    timeline
}

fn find_token_position(timeline: &[(String, u64)], ts: &str) -> u64 {
    if timeline.is_empty() {
        return 0;
    }
    // Find the last entry at or before this timestamp
    let mut best = 0u64;
    for (entry_ts, tokens_k) in timeline {
        if entry_ts.as_str() <= ts {
            best = *tokens_k;
        } else {
            break;
        }
    }
    best
}

// ── Event loading ─────────────────────────────────────────────

fn load_session_events(content: &str, session_id: &str) -> Vec<WayEvent> {
    content
        .lines()
        .filter(|l| l.contains(session_id))
        .filter_map(|line| {
            let v: serde_json::Value = serde_json::from_str(line).ok()?;
            if v["session"].as_str()? != session_id {
                return None;
            }
            Some(WayEvent {
                ts: v["ts"].as_str().unwrap_or("").to_string(),
                event: v["event"].as_str().unwrap_or("").to_string(),
                way: v["way"].as_str().unwrap_or("").to_string(),
                trigger: v["trigger"].as_str().unwrap_or("").to_string(),
                scope: v["scope"].as_str().unwrap_or("").to_string(),
                check: v["check"].as_str().unwrap_or("").to_string(),
                token_position: v["token_position"]
                    .as_str()
                    .and_then(|s| s.parse().ok())
                    .unwrap_or(0),
            })
        })
        .collect()
}

fn find_session_project(content: &str, session_id: &str) -> Option<String> {
    for line in content.lines() {
        if !line.contains(session_id) || !line.contains("session_start") {
            continue;
        }
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(line) {
            if v["session"].as_str() == Some(session_id) {
                return v["project"].as_str().map(|s| s.to_string());
            }
        }
    }
    None
}

// ── Session listing and picker ────────────────────────────────

struct SessionInfo {
    id: String,
    ts: String,
    project: String,
    event_count: u32,
    way_fires: u32,
    duration_secs: u64,
}

fn gather_sessions(content: &str, project_filter: Option<&str>) -> Vec<SessionInfo> {
    let mut sessions: Vec<SessionInfo> = Vec::new();
    let mut event_counts: HashMap<String, (u32, u32)> = HashMap::new(); // (total, way_fires)
    let mut last_ts: HashMap<String, String> = HashMap::new();

    for line in content.lines() {
        if line.is_empty() {
            continue;
        }
        let v: serde_json::Value = match serde_json::from_str(line) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let sid = match v["session"].as_str() {
            Some(s) if !s.is_empty() => s.to_string(),
            _ => continue,
        };

        let event = v["event"].as_str().unwrap_or("");
        let ts = v["ts"].as_str().unwrap_or("").to_string();

        if event == "session_start" {
            let project = v["project"].as_str().unwrap_or("").to_string();
            if let Some(pf) = project_filter {
                if !project.contains(pf) {
                    continue;
                }
            }
            sessions.push(SessionInfo {
                id: sid.clone(),
                ts: ts.clone(),
                project,
                event_count: 0,
                way_fires: 0,
                duration_secs: 0,
            });
        }

        let counts = event_counts.entry(sid.clone()).or_insert((0, 0));
        counts.0 += 1;
        if event == "way_fired" {
            counts.1 += 1;
        }
        last_ts.insert(sid, ts);
    }

    // Backfill counts and duration
    for s in &mut sessions {
        if let Some((total, fires)) = event_counts.get(&s.id) {
            s.event_count = *total;
            s.way_fires = *fires;
        }
        if let Some(last) = last_ts.get(&s.id) {
            let start = parse_ts_secs(&s.ts);
            let end = parse_ts_secs(last);
            s.duration_secs = end.saturating_sub(start);
        }
    }

    sessions
}

fn list_sessions(content: &str, project_filter: Option<&str>) -> Result<()> {
    let sessions = gather_sessions(content, project_filter);
    if sessions.is_empty() {
        println!("No sessions found.");
        return Ok(());
    }

    println!();
    println!(
        "\x1b[1m{:<14} {:<20} {:<30} {:>6} {:>6} {:>8}\x1b[0m",
        "Session", "Date", "Project", "Events", "Ways", "Duration"
    );
    println!("\x1b[2m{}\x1b[0m", "─".repeat(90));

    for s in sessions.iter().rev().take(50) {
        let short_id = &s.id[..s.id.len().min(12)];
        let date = &s.ts[..s.ts.len().min(16)];
        let project_short = s.project.split('/').last().unwrap_or(&s.project);
        let duration = format_duration(s.duration_secs);
        println!(
            "  {:<12} {:<20} {:<30} {:>6} {:>6} {:>8}",
            short_id, date, project_short, s.event_count, s.way_fires, duration
        );
    }
    println!();
    println!("\x1b[2m  {} sessions total. Use --session <id> or run without args for interactive picker.\x1b[0m", sessions.len());
    println!();
    Ok(())
}

#[cfg(feature = "tui")]
fn pick_session(content: &str, project_filter: Option<&str>) -> Option<String> {
    let sessions = gather_sessions(content, project_filter);
    if sessions.is_empty() {
        println!("No sessions found.");
        return None;
    }

    // Show most recent first
    let sessions: Vec<&SessionInfo> = sessions.iter().rev().collect();
    let mut selected: usize = 0;
    let page_size = 20usize;
    let mut stdout = std::io::stdout();

    terminal::enable_raw_mode().ok()?;
    execute!(stdout, terminal::EnterAlternateScreen, cursor::Hide).ok()?;

    let result = pick_session_loop(&sessions, &mut selected, page_size, &mut stdout);

    execute!(stdout, cursor::Show, terminal::LeaveAlternateScreen).ok();
    terminal::disable_raw_mode().ok();

    result
}

#[cfg(feature = "tui")]
fn pick_session_loop(
    sessions: &[&SessionInfo],
    selected: &mut usize,
    page_size: usize,
    stdout: &mut std::io::Stdout,
) -> Option<String> {
    loop {
        // Render picker
        let (tw, th) = terminal::size().unwrap_or((120, 40));
        let mut out = String::new();
        let _ = writeln!(out, "");
        let _ = writeln!(
            out,
            "\x1b[1m  Select a session to replay\x1b[0m  \x1b[2m({} sessions)\x1b[0m",
            sessions.len()
        );
        let _ = writeln!(out, "");
        let _ = writeln!(
            out,
            "  \x1b[1m{:<14} {:<18} {:<28} {:>5} {:>5} {:>8}\x1b[0m",
            "Session", "Date", "Project", "Evts", "Ways", "Duration"
        );
        let _ = writeln!(out, "  \x1b[2m{}\x1b[0m", "─".repeat(82));

        // Page calculation
        let page_start = (*selected / page_size) * page_size;
        let page_end = (page_start + page_size).min(sessions.len());

        for i in page_start..page_end {
            let s = sessions[i];
            let short_id = &s.id[..s.id.len().min(12)];
            let date = &s.ts[..s.ts.len().min(16)];
            let project_short = s.project.split('/').last().unwrap_or(&s.project);
            let duration = format_duration(s.duration_secs);

            let (prefix, suffix) = if i == *selected {
                ("\x1b[7m", "\x1b[0m") // inverse video for selected
            } else {
                ("", "")
            };

            let _ = writeln!(
                out,
                "  {prefix}{:<12}  {:<18} {:<28} {:>5} {:>5} {:>8}{suffix}",
                short_id, date, project_short, s.event_count, s.way_fires, duration
            );
        }

        let _ = writeln!(out, "");
        let _ = writeln!(
            out,
            "  \x1b[2mPage {}/{}\x1b[0m",
            *selected / page_size + 1,
            (sessions.len() + page_size - 1) / page_size
        );
        let _ = writeln!(out, "");
        let _ = write!(
            out,
            "\x1b[2m{}\x1b[0m\r\n \x1b[7m ▲▼ \x1b[0m select  \x1b[7m ⏎ \x1b[0m replay  \x1b[7m esc \x1b[0m quit",
            "─".repeat(85)
        );

        let fitted = fit_to_terminal(&out, tw as usize, th as usize);
        execute!(stdout, cursor::MoveTo(0, 0), terminal::Clear(ClearType::All)).ok();
        write!(stdout, "{fitted}").ok();
        stdout.flush().ok();

        // Wait for input
        if let Ok(Event::Key(key)) = event::read() {
            match key {
                KeyEvent { code: KeyCode::Esc, .. }
                | KeyEvent { code: KeyCode::Char('q'), .. } => return None,

                KeyEvent { code: KeyCode::Char('c'), modifiers: KeyModifiers::CONTROL, .. } => return None,

                KeyEvent { code: KeyCode::Enter, .. } => {
                    return Some(sessions[*selected].id.clone());
                }

                KeyEvent { code: KeyCode::Up, .. }
                | KeyEvent { code: KeyCode::Char('k'), .. } => {
                    if *selected > 0 {
                        *selected -= 1;
                    }
                }

                KeyEvent { code: KeyCode::Down, .. }
                | KeyEvent { code: KeyCode::Char('j'), .. } => {
                    if *selected < sessions.len() - 1 {
                        *selected += 1;
                    }
                }

                KeyEvent { code: KeyCode::PageUp, .. } => {
                    *selected = selected.saturating_sub(page_size);
                }

                KeyEvent { code: KeyCode::PageDown, .. } => {
                    *selected = (*selected + page_size).min(sessions.len() - 1);
                }

                KeyEvent { code: KeyCode::Home, .. }
                | KeyEvent { code: KeyCode::Char('g'), .. } => {
                    *selected = 0;
                }

                KeyEvent { code: KeyCode::End, .. }
                | KeyEvent { code: KeyCode::Char('G'), .. } => {
                    *selected = sessions.len() - 1;
                }

                _ => {}
            }
        }
    }
}

#[cfg(not(feature = "tui"))]
fn pick_session(_content: &str, _project_filter: Option<&str>) -> Option<String> {
    eprintln!("Interactive picker requires the 'tui' feature.");
    None
}

fn format_duration(secs: u64) -> String {
    if secs < 60 {
        format!("{secs}s")
    } else if secs < 3600 {
        format!("{}m {}s", secs / 60, secs % 60)
    } else {
        let h = secs / 3600;
        let m = (secs % 3600) / 60;
        format!("{h}h {m}m")
    }
}

fn detect_context_window_for_session(project: &str, session_id: &str) -> u64 {
    let project_slug = project.replace(['/', '.'], "-");
    let transcript = home_dir()
        .join(format!(".claude/projects/{project_slug}/{session_id}.jsonl"));

    let content = match std::fs::read_to_string(&transcript) {
        Ok(c) => c,
        Err(_) => return 200,
    };

    for line in content.lines().rev() {
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(line) {
            if val.get("type").and_then(|t| t.as_str()) == Some("assistant") {
                if let Some(model) = val.get("message").and_then(|m| m.get("model")).and_then(|m| m.as_str()) {
                    if model.contains("opus-4") {
                        return 1000;
                    }
                }
                break;
            }
        }
    }
    200
}

// ── Helpers ───────────────────────────────────────────────────

fn parse_ts_secs(ts: &str) -> u64 {
    // Parse ISO 8601: "2026-03-16T19:08:39Z"
    if ts.len() < 19 {
        return 0;
    }
    let year: u64 = ts[0..4].parse().unwrap_or(0);
    let month: u64 = ts[5..7].parse().unwrap_or(0);
    let day: u64 = ts[8..10].parse().unwrap_or(0);
    let hour: u64 = ts[11..13].parse().unwrap_or(0);
    let min: u64 = ts[14..16].parse().unwrap_or(0);
    let sec: u64 = ts[17..19].parse().unwrap_or(0);

    // Approximate seconds since epoch (good enough for relative timing)
    let days = year * 365 + year / 4 + month * 30 + day;
    days * 86400 + hour * 3600 + min * 60 + sec
}

fn predict_next(w: &ActiveWay, current_epoch: u64, current_tokens_k: u64, redisclose_threshold_k: u64) -> String {
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

    let epoch_distance = current_epoch.saturating_sub(w.epoch_fired);
    if w.check_fires > 0 {
        let decay = 1.0 / (w.check_fires as f64 + 1.0);
        let needed_factor = 2.0 / (3.0 * decay);
        let needed_distance = ((needed_factor - 1.0).exp() - 1.0).max(0.0) as u64;
        let next_epoch = w.epoch_fired + needed_distance;
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
        "semantic:bm25" | "semantic" => "bm25".to_string(),
        "semantic:embedding" => "embed".to_string(),
        "keyword" => "keyword".to_string(),
        "check-pull" => "check-pull".to_string(),
        "bash" | "file" | "state" => trigger.to_string(),
        _ => trigger.to_string(),
    }
}

/// Fit rendered output to terminal dimensions.
/// Truncates each line to visible width (ANSI-aware) and limits total lines.
/// Uses \r\n because raw mode requires explicit carriage return.
fn fit_to_terminal(output: &str, width: usize, height: usize) -> String {
    let mut result = String::new();
    let mut line_count = 0;
    let max_lines = height.saturating_sub(1);

    for line in output.lines() {
        if line_count >= max_lines {
            break;
        }
        result.push_str(&truncate_visible(line, width));
        result.push_str("\r\n");
        line_count += 1;
    }
    result
}

/// Truncate a string to `max_visible` visible characters, preserving ANSI escapes.
fn truncate_visible(s: &str, max_visible: usize) -> String {
    let mut result = String::new();
    let mut visible = 0;
    let mut in_escape = false;

    for ch in s.chars() {
        if in_escape {
            result.push(ch);
            if ch.is_ascii_alphabetic() {
                in_escape = false;
            }
            continue;
        }
        if ch == '\x1b' {
            in_escape = true;
            result.push(ch);
            continue;
        }
        if visible >= max_visible {
            break;
        }
        result.push(ch);
        // Most Unicode chars are 1 column wide; CJK would be 2 but we don't use them
        visible += 1;
    }
    // Reset any dangling style
    if result.contains('\x1b') {
        result.push_str("\x1b[0m");
    }
    result
}

fn truncate(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max - 1])
    }
}
