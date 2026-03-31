//! Shared utility functions used across multiple modules.

use std::path::{Path, PathBuf};

/// Home directory from $HOME, falling back to /tmp.
pub fn home_dir() -> PathBuf {
    std::env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"))
}

/// Detect the project root by walking up from cwd looking for .claude/settings.json or CLAUDE.md.
pub fn detect_project_dir() -> Option<String> {
    let cwd = std::env::current_dir().ok()?;
    let mut dir = cwd.as_path();
    loop {
        let claude_dir = dir.join(".claude");
        if claude_dir.is_dir()
            && (claude_dir.join("settings.json").exists()
                || dir.join("CLAUDE.md").exists()
                || claude_dir.join("settings.local.json").exists())
        {
            return Some(dir.to_string_lossy().to_string());
        }
        dir = dir.parent()?;
    }
}

/// Load excluded path segments from frontmatter-schema.yaml.
/// Returns empty vec if schema can't be read (non-fatal).
pub fn load_excluded_segments() -> Vec<String> {
    let schema_path = home_dir().join(".claude/hooks/ways/frontmatter-schema.yaml");
    let content = match std::fs::read_to_string(&schema_path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    let doc: serde_yaml::Value = match serde_yaml::from_str(&content) {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };
    doc.get("lint")
        .and_then(|v| v.get("excluded_path_segments"))
        .and_then(|v| v.as_sequence())
        .map(|seq| {
            seq.iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect()
        })
        .unwrap_or_default()
}

/// Check if a path should be excluded based on schema-defined segments.
pub fn is_excluded_path(path: &Path, excluded_segments: &[String]) -> bool {
    let path_str = match path.to_str() {
        Some(s) => s,
        None => return false,
    };
    for segment in excluded_segments {
        if path_str.contains(segment.as_str()) {
            return true;
        }
    }
    // Timestamp filenames from sync tools (e.g., 2026-03-30T13_13_26.616Z.Desktop.md)
    if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
        let stem = stem.strip_suffix(".check").unwrap_or(stem);
        if stem.starts_with("20") && stem.contains('T') && stem.contains('.') {
            return true;
        }
    }
    false
}
