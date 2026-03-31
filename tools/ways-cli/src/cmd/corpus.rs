use anyhow::{Context, Result};
use serde_json::json;
use std::collections::HashMap;
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

use crate::frontmatter;

pub fn run(ways_dir: Option<String>, quiet: bool, if_stale: bool) -> Result<()> {
    let global_dir = ways_dir
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".claude/hooks/ways"));

    let xdg_way = xdg_cache_dir().join("claude-ways/user");

    // Staleness check: skip regen if corpus is fresh
    if if_stale {
        let manifest = xdg_way.join("embed-manifest.json");
        let corpus = xdg_way.join("ways-corpus.jsonl");
        if manifest.is_file() && corpus.is_file() {
            let project_dir = std::env::var("CLAUDE_PROJECT_DIR").unwrap_or_default();
            if !is_stale(&manifest, &global_dir, &project_dir) {
                return Ok(());
            }
        }
        // Missing manifest/corpus → always regen
    }
    std::fs::create_dir_all(&xdg_way)?;
    let output = xdg_way.join("ways-corpus.jsonl");

    let tmpfile = output.with_extension("jsonl.tmp");
    let mut w = BufWriter::new(
        std::fs::File::create(&tmpfile)
            .with_context(|| format!("creating {}", tmpfile.display()))?,
    );

    let log = |msg: &str| {
        if !quiet {
            eprintln!("{msg}");
        }
    };

    let excluded = crate::util::load_excluded_segments();

    // Scan global ways
    let global_count = scan_ways_dir(&global_dir, "", &excluded, &mut w)?;
    let global_hash = content_hash(&global_dir);
    log(&format!(
        "Global ways: {global_count} (hash: {}...)",
        &global_hash[..16.min(global_hash.len())]
    ));

    // Scan project-local ways
    let projects_dir = home_dir().join(".claude/projects");
    let mut project_total = 0;
    let mut manifest_projects: HashMap<String, serde_json::Value> = HashMap::new();

    let mut seen_ways_dirs: std::collections::HashSet<PathBuf> = std::collections::HashSet::new();

    if projects_dir.is_dir() {
        for entry in std::fs::read_dir(&projects_dir)? {
            let entry = entry?;
            if !entry.file_type()?.is_dir() {
                continue;
            }

            let encoded = entry.file_name().to_string_lossy().to_string();
            let project_path = match resolve_project_path(&projects_dir, &encoded) {
                Some(p) => p,
                None => continue,
            };

            // Walk up to find .claude/ways/ (project may be invoked from subdirectory)
            let ways_path = match find_ways_dir(&project_path) {
                Some(p) => p,
                None => continue,
            };

            // Dedup: multiple encoded dirs may resolve to the same .claude/ways/
            if !seen_ways_dirs.insert(ways_path.clone()) {
                continue;
            }

            // Check .ways-embed marker
            let marker_dir = ways_path.parent().unwrap_or(Path::new(""));
            let marker = marker_dir.join(".ways-embed");
            if marker.is_file() {
                let state = std::fs::read_to_string(&marker)
                    .unwrap_or_default()
                    .trim()
                    .to_string();
                if state == "disinclude" {
                    continue;
                }
            }

            let prefix = format!("{encoded}/");
            let local_count = scan_ways_dir(&ways_path, &prefix, &excluded, &mut w)?;

            if local_count > 0 {
                project_total += local_count;
                let local_hash = content_hash(&ways_path);
                log(&format!(
                    "  {}: {local_count} ways (hash: {}...)",
                    project_path,
                    &local_hash[..16.min(local_hash.len())]
                ));
                manifest_projects.insert(
                    encoded.clone(),
                    json!({
                        "path": &project_path,
                        "ways_hash": local_hash,
                        "ways_count": local_count,
                    }),
                );
            }
        }
    }

    w.flush()?;
    drop(w);

    // Atomic move
    std::fs::rename(&tmpfile, &output)?;

    let total = global_count + project_total;
    log(&format!(
        "Generated {}: {total} ways ({global_count} global, {project_total} project)",
        output.display()
    ));

    // Auto-embed if way-embed binary and model are available
    auto_embed(&xdg_way, &output, &log)?;

    // Write manifest
    let manifest = json!({
        "global_hash": global_hash,
        "global_count": global_count,
        "total_count": total,
        "projects": manifest_projects,
    });
    let manifest_path = xdg_way.join("embed-manifest.json");
    std::fs::write(&manifest_path, serde_json::to_string_pretty(&manifest)?)?;
    log(&format!("Manifest written: {}", manifest_path.display()));

    Ok(())
}

/// Scan a ways directory for semantic ways (having description + vocabulary).
/// Writes JSONL to the writer. Returns the number of ways found.
fn scan_ways_dir(dir: &Path, id_prefix: &str, excluded: &[String], w: &mut impl Write) -> Result<usize> {
    let mut count = 0;

    let mut files: Vec<PathBuf> = Vec::new();
    for entry in WalkDir::new(dir)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        if !path.is_file() || path.extension().and_then(|e| e.to_str()) != Some("md") {
            continue;
        }
        if path
            .file_name()
            .and_then(|n| n.to_str())
            .map_or(false, |n| n.contains(".check."))
        {
            continue;
        }
        if crate::util::is_excluded_path(path, excluded) {
            continue;
        }
        files.push(path.to_path_buf());
    }
    files.sort();

    for path in &files {
        let fm = match frontmatter::parse(path) {
            Ok(fm) => fm,
            Err(_) => continue,
        };

        // Skip ways without semantic fields (corpus is for matching engines)
        if fm.description.is_empty() || fm.vocabulary.is_none() {
            continue;
        }

        let relpath = path.strip_prefix(dir).unwrap_or(path);
        let id = format!(
            "{}{}",
            id_prefix,
            relpath.parent().unwrap_or(Path::new("")).display()
        );

        let entry = json!({
            "id": id,
            "description": fm.description,
            "vocabulary": fm.vocabulary.unwrap_or_default(),
            "threshold": fm.threshold.unwrap_or(2.0),
            "embed_threshold": fm.embed_threshold.unwrap_or(0.35),
        });

        serde_json::to_writer(&mut *w, &entry)?;
        w.write_all(b"\n")?;
        count += 1;
    }

    Ok(count)
}

/// Shell out to way-embed generate for embedding vectors.
fn auto_embed(xdg_way: &Path, corpus: &Path, log: &dyn Fn(&str)) -> Result<()> {
    let embed_bin = [
        xdg_way.join("way-embed"),
        home_dir().join(".claude/bin/way-embed"),
    ]
    .into_iter()
    .find(|p| p.is_file());

    let model = xdg_way.join("minilm-l6-v2.gguf");

    if let Some(bin) = embed_bin {
        if model.is_file() {
            log("Embedding model found — generating embedding vectors...");
            let status = std::process::Command::new(&bin)
                .args(["generate", "--corpus"])
                .arg(corpus)
                .args(["--model"])
                .arg(&model)
                .stderr(std::process::Stdio::null())
                .status();

            match status {
                Ok(s) if s.success() => log(&format!("Embeddings added to {}", corpus.display())),
                _ => eprintln!("WARNING: embedding generation failed, corpus has BM25 fields only"),
            }
        }
    } else {
        log("Tip: install the embedding engine for 98% matching accuracy (vs 91% BM25):");
        log("  cd ~/.claude && make setup");
    }

    Ok(())
}

/// Resolve real project path from Claude Code's encoded directory name.
/// The encoding (/ → -) is lossy, so we try sessions-index.json first,
/// then fall back to greedy filesystem resolution.
fn resolve_project_path(projects_dir: &Path, encoded: &str) -> Option<String> {
    // Try sessions-index.json first
    let idx = projects_dir.join(encoded).join("sessions-index.json");
    if idx.is_file() {
        if let Ok(content) = std::fs::read_to_string(&idx) {
            if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(path) = parsed["entries"][0]["projectPath"].as_str() {
                    if !path.is_empty() {
                        return Some(path.to_string());
                    }
                }
            }
        }
    }

    // Fallback: greedy filesystem resolution
    resolve_encoded_path(encoded)
}

/// Greedily resolve an encoded path against the filesystem.
/// Splits on -, accumulates segments, tests filesystem at each step
/// to distinguish / from - in the original path.
/// e.g., "-home-aaron-Projects-app-github-manager" → "/home/aaron/Projects/app/github-manager"
fn resolve_encoded_path(encoded: &str) -> Option<String> {
    let stripped = encoded.strip_prefix('-').unwrap_or(encoded);
    let segments: Vec<&str> = stripped.split('-').collect();

    let mut current = String::new();
    let mut pending = String::new();

    for seg in &segments {
        if pending.is_empty() {
            let try_path = format!("{current}/{seg}");
            if Path::new(&try_path).is_dir() {
                current = try_path;
            } else {
                pending = seg.to_string();
            }
        } else {
            // Try hyphenated: current/pending-seg
            let try_hyphen = format!("{current}/{pending}-{seg}");
            // Try split: current/pending/seg
            let try_split = format!("{current}/{pending}/{seg}");

            if Path::new(&try_hyphen).is_dir() {
                current = try_hyphen;
                pending.clear();
            } else if Path::new(&try_split).is_dir() {
                current = try_split;
                pending.clear();
            } else {
                pending = format!("{pending}-{seg}");
            }
        }
    }

    // Flush pending
    if !pending.is_empty() {
        let try_path = format!("{current}/{pending}");
        if Path::new(&try_path).is_dir() {
            current = try_path;
        } else {
            return None;
        }
    }

    if Path::new(&current).is_dir() {
        Some(current)
    } else {
        None
    }
}

/// Walk up from a project path to find .claude/ways/ directory.
fn find_ways_dir(project_path: &str) -> Option<PathBuf> {
    let home = home_dir();
    let mut check = PathBuf::from(project_path);
    while check != Path::new("/") && check != home {
        let candidate = check.join(".claude/ways");
        if candidate.is_dir() {
            return Some(candidate);
        }
        check = check.parent()?.to_path_buf();
    }
    None
}

/// Content hash of a directory (sorted file list + sizes).
fn content_hash(dir: &Path) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    let mut entries: Vec<(String, u64)> = Vec::new();

    for entry in WalkDir::new(dir)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        if entry.path().is_file() {
            let rel = entry.path().strip_prefix(dir).unwrap_or(entry.path());
            let size = entry.metadata().map(|m| m.len()).unwrap_or(0);
            entries.push((rel.display().to_string(), size));
        }
    }
    entries.sort();
    entries.hash(&mut hasher);

    format!("{:016x}", hasher.finish())
}

use crate::util::home_dir;

fn xdg_cache_dir() -> PathBuf {
    std::env::var("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| home_dir().join(".cache"))
}

/// Check if any way file is newer than the manifest.
fn is_stale(manifest: &Path, global_dir: &Path, project_dir: &str) -> bool {
    // Check global ways
    for entry in WalkDir::new(global_dir)
        .follow_links(true)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        if path.is_file() && path.extension().and_then(|e| e.to_str()) == Some("md") {
            if is_newer_than(path, manifest) {
                return true;
            }
        }
    }

    // Check project ways
    if !project_dir.is_empty() {
        let project_ways = Path::new(project_dir).join(".claude/ways");
        if project_ways.is_dir() {
            for entry in WalkDir::new(&project_ways)
                .follow_links(true)
                .into_iter()
                .filter_map(|e| e.ok())
            {
                let path = entry.path();
                if path.is_file() && path.extension().and_then(|e| e.to_str()) == Some("md") {
                    if is_newer_than(path, manifest) {
                        return true;
                    }
                }
            }
        }
    }

    false
}

fn is_newer_than(file: &Path, reference: &Path) -> bool {
    let file_mtime = file.metadata().and_then(|m| m.modified()).ok();
    let ref_mtime = reference.metadata().and_then(|m| m.modified()).ok();
    match (file_mtime, ref_mtime) {
        (Some(f), Some(r)) => f > r,
        _ => false,
    }
}
