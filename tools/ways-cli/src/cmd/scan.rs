//! Scan ways and output matched content — replaces hook scan loops.
//!
//! Combines file walking, frontmatter extraction, matching (pattern + semantic),
//! scope/precondition gating, parent-threshold lowering, and show (display).

use anyhow::Result;
use regex::Regex;
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

use crate::bm25;
use crate::cmd::show;
use crate::session;

struct WayCandidate {
    id: String,
    path: PathBuf,
    pattern: Option<String>,
    commands: Option<String>,
    files: Option<String>,
    description: String,
    vocabulary: String,
    threshold: f64,
    scope: String,
    when_project: Option<String>,
    when_file_exists: Option<String>,
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
            let _ = show::way(&way.id, session_id, &trigger);
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
    // Channel 1: Regex pattern
    if let Some(ref pat) = pattern {
        if regex_matches(pat, query) {
            return Some("keyword".to_string());
        }
    }

    // Channel 2: Embedding (highest priority semantic)
    if embed.iter().any(|(id, _)| id == way_id) {
        return Some("semantic:embedding".to_string());
    }

    // Channel 3: BM25
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

// ── Batch scoring ───────────────────────────────────────────────

fn batch_bm25_score(query: &str) -> Vec<(String, f64)> {
    let corpus_path = default_corpus();
    if !corpus_path.exists() {
        return Vec::new();
    }

    let stemmer = bm25::new_stemmer();
    let corpus = match bm25::load_corpus_jsonl(corpus_path.to_str().unwrap_or(""), &stemmer) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    let query_tokens = bm25::tokenize(query, &stemmer);
    corpus
        .docs
        .iter()
        .map(|doc| {
            let score = corpus.bm25_score(doc, &query_tokens);
            let threshold = if doc.threshold > 0.0 {
                doc.threshold
            } else {
                2.0
            };
            (doc.id.clone(), if score >= threshold { score } else { 0.0 })
        })
        .filter(|(_, s)| *s > 0.0)
        .collect()
}

fn batch_embed_score(query: &str) -> Vec<(String, f64)> {
    let ways_bin = home_dir().join(".claude/bin/ways");
    if !ways_bin.is_file() {
        return Vec::new();
    }

    let output = std::process::Command::new(&ways_bin)
        .args(["embed", query])
        .output();

    match output {
        Ok(o) if o.status.success() => {
            String::from_utf8_lossy(&o.stdout)
                .lines()
                .filter_map(|line| {
                    let mut parts = line.split('\t');
                    let id = parts.next()?.to_string();
                    let score: f64 = parts.next()?.parse().ok()?;
                    Some((id, score))
                })
                .collect()
        }
        _ => Vec::new(),
    }
}

// ── Candidate collection ────────────────────────────────────────

fn collect_candidates(project_dir: &str) -> Vec<WayCandidate> {
    let mut candidates = Vec::new();

    // Project-local first
    let project_ways = PathBuf::from(project_dir).join(".claude/ways");
    if project_ways.is_dir() {
        collect_from_dir(&project_ways, &mut candidates);
    }

    // Global
    let global_ways = home_dir().join(".claude/hooks/ways");
    collect_from_dir(&global_ways, &mut candidates);

    candidates
}

fn collect_checks(project_dir: &str) -> Vec<WayCandidate> {
    let mut candidates = Vec::new();

    let project_ways = PathBuf::from(project_dir).join(".claude/ways");
    if project_ways.is_dir() {
        collect_checks_from_dir(&project_ways, &mut candidates);
    }

    let global_ways = home_dir().join(".claude/hooks/ways");
    collect_checks_from_dir(&global_ways, &mut candidates);

    candidates
}

fn collect_from_dir(dir: &Path, out: &mut Vec<WayCandidate>) {
    for entry in WalkDir::new(dir)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        if !path.is_file() || path.extension().and_then(|e| e.to_str()) != Some("md") {
            continue;
        }
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        if name.contains(".check.") {
            continue;
        }

        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        if !content.starts_with("---\n") {
            continue;
        }

        let id = way_id_from_path(path, dir);
        if id.is_empty() {
            continue;
        }

        // Check domain disable
        let domain = id.split('/').next().unwrap_or(&id);
        if session::domain_disabled(domain) {
            continue;
        }

        if let Some(candidate) = parse_candidate(&id, path, &content) {
            out.push(candidate);
        }
    }
}

fn collect_checks_from_dir(dir: &Path, out: &mut Vec<WayCandidate>) {
    for entry in WalkDir::new(dir)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
        if !name.contains(".check.md") {
            continue;
        }

        let content = match std::fs::read_to_string(path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        if !content.starts_with("---\n") {
            continue;
        }

        let id = way_id_from_path(path, dir);
        if id.is_empty() {
            continue;
        }

        if let Some(candidate) = parse_candidate(&id, path, &content) {
            out.push(candidate);
        }
    }
}

fn parse_candidate(id: &str, path: &Path, content: &str) -> Option<WayCandidate> {
    let fm = extract_frontmatter(content)?;

    Some(WayCandidate {
        id: id.to_string(),
        path: path.to_path_buf(),
        pattern: get_fm_field(&fm, "pattern"),
        commands: get_fm_field(&fm, "commands"),
        files: get_fm_field(&fm, "files"),
        description: get_fm_field(&fm, "description").unwrap_or_default(),
        vocabulary: get_fm_field(&fm, "vocabulary").unwrap_or_default(),
        threshold: get_fm_field(&fm, "threshold")
            .and_then(|s| s.parse().ok())
            .unwrap_or(2.0),
        scope: get_fm_field(&fm, "scope").unwrap_or_else(|| "agent".to_string()),
        when_project: get_when_field(&fm, "project"),
        when_file_exists: get_when_field(&fm, "file_exists"),
    })
}

// ── Helpers ─────────────────────────────────────────────────────

fn capture_show_way(id: &str, session_id: &str, trigger: &str) -> String {
    // Capture stdout from show::way by redirecting
    let output = std::process::Command::new(std::env::current_exe().unwrap_or_else(|_| PathBuf::from("ways")))
        .args(["show", "way", id, "--session", session_id, "--trigger", trigger])
        .env(
            "CLAUDE_PROJECT_DIR",
            std::env::var("CLAUDE_PROJECT_DIR").unwrap_or_default(),
        )
        .output();

    match output {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).to_string(),
        _ => String::new(),
    }
}

fn capture_show_check(id: &str, session_id: &str, trigger: &str, score: f64) -> String {
    let output = std::process::Command::new(std::env::current_exe().unwrap_or_else(|_| PathBuf::from("ways")))
        .args([
            "show", "check", id,
            "--session", session_id,
            "--trigger", trigger,
            "--score", &format!("{score:.2}"),
        ])
        .env(
            "CLAUDE_PROJECT_DIR",
            std::env::var("CLAUDE_PROJECT_DIR").unwrap_or_default(),
        )
        .output();

    match output {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout).to_string(),
        _ => String::new(),
    }
}

fn check_when(
    when_project: &Option<String>,
    when_file_exists: &Option<String>,
    project_dir: &str,
) -> bool {
    if when_project.is_none() && when_file_exists.is_none() {
        return true;
    }

    if let Some(ref wp) = when_project {
        let expanded = wp.replace("~", &home_dir().display().to_string());
        let resolved = std::fs::canonicalize(&expanded)
            .unwrap_or_else(|_| PathBuf::from(&expanded));
        let current = std::fs::canonicalize(project_dir)
            .unwrap_or_else(|_| PathBuf::from(project_dir));
        if resolved != current {
            return false;
        }
    }

    if let Some(ref wfe) = when_file_exists {
        let resolved_dir = std::fs::canonicalize(project_dir)
            .unwrap_or_else(|_| PathBuf::from(project_dir));
        if !resolved_dir.join(wfe).exists() {
            return false;
        }
    }

    true
}

fn way_id_from_path(path: &Path, base: &Path) -> String {
    let parent = path.parent().unwrap_or(path);
    parent
        .strip_prefix(base)
        .unwrap_or(parent)
        .display()
        .to_string()
}

fn extract_frontmatter(content: &str) -> Option<String> {
    if !content.starts_with("---\n") {
        return None;
    }
    let rest = &content[4..];
    let end = rest.find("\n---\n").or_else(|| rest.find("\n---"))?;
    Some(rest[..end].to_string())
}

fn get_fm_field(fm: &str, name: &str) -> Option<String> {
    let prefix = format!("{name}:");
    for line in fm.lines() {
        if let Some(val) = line.strip_prefix(&prefix) {
            let val = val.trim();
            if !val.is_empty() {
                return Some(val.to_string());
            }
        }
    }
    None
}

fn get_when_field(fm: &str, name: &str) -> Option<String> {
    let mut in_when = false;
    let prefix = format!("  {name}:");
    for line in fm.lines() {
        if line == "when:" {
            in_when = true;
            continue;
        }
        if in_when {
            if let Some(val) = line.strip_prefix(&prefix) {
                return Some(val.trim().to_string());
            }
            if !line.starts_with("  ") && !line.is_empty() {
                break;
            }
        }
    }
    None
}

fn default_project() -> String {
    std::env::var("CLAUDE_PROJECT_DIR")
        .unwrap_or_else(|_| std::env::var("PWD").unwrap_or_else(|_| ".".to_string()))
}

fn default_corpus() -> PathBuf {
    let xdg = std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home_dir().join(".cache"));
    xdg.join("claude-ways/user/ways-corpus.jsonl")
}

fn home_dir() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}
