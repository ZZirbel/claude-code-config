#!/bin/bash
# Generate ways-corpus.jsonl from all semantic way.md files
#
# Scans global ways and project-local ways into a unified corpus.
# Extracts frontmatter fields and emits one JSON line per way.
#
# Output is a generated cache in XDG_CACHE_HOME — not tracked in git.
# Runtime scanners read it; regen happens via `make setup` or `make test`.
#
# After generation, writes embed-manifest.json with content hashes for
# staleness detection (ADR-109). The manifest records what was embedded
# so session-start checks can detect when regen is needed.
#
# Usage: generate-corpus.sh [--quiet] [ways-dir] [output-file]
#   --quiet:     suppress progress output (for use in test/lint pipelines)
#   ways-dir:    directory to scan for global ways (default: ~/.claude/hooks/ways)
#   output-file: where to write JSONL (default: ~/.cache/claude-ways/user/ways-corpus.jsonl)

QUIET=false
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  B='' D='' C='' R=''
  if [[ -t 1 ]]; then B='\033[1m' D='\033[2m' C='\033[0;36m' R='\033[0m'; fi
  echo -e "${B}embed-corpus${R} — Generate unified ways embedding corpus"
  echo ""
  echo -e "  ${C}Usage:${R}  embed-corpus [--quiet] [ways-dir] [output-file]"
  echo ""
  echo -e "  ${D}--quiet       Suppress progress output (for pipelines)${R}"
  echo -e "  ${D}ways-dir      Global ways directory (default: ~/.claude/hooks/ways)${R}"
  echo -e "  ${D}output-file   Corpus path (default: ~/.cache/claude-ways/user/ways-corpus.jsonl)${R}"
  echo ""
  echo -e "  ${D}Scans global + project-local ways, embeds into single corpus,${R}"
  echo -e "  ${D}writes embed-manifest.json for staleness detection.${R}"
  exit 0
fi
[[ "${1:-}" == "--quiet" ]] && { QUIET=true; shift; }

WAYS_DIR="${1:-${HOME}/.claude/hooks/ways}"
XDG_WAY="${XDG_CACHE_HOME:-$HOME/.cache}/claude-ways/user"
OUTPUT="${2:-${XDG_WAY}/ways-corpus.jsonl}"
PROJECTS_DIR="${HOME}/.claude/projects"
LINT_SCRIPT="${HOME}/.claude/hooks/ways/lint-ways.sh"
mkdir -p "$XDG_WAY"

log() { $QUIET || echo "$@" >&2; }

# Guard against infinite recursion with lint-ways.sh
export GENERATE_CORPUS_RUNNING=1

# Temp file for atomic write
TMPFILE="${OUTPUT}.tmp.$$"
trap 'rm -f "$TMPFILE"' EXIT

# ── Shared library ───────────────────────────────────────────────
# Provides: content_hash, resolve_project_path, json_escape
EMBED_LIB="${HOME}/.claude/hooks/ways/embed-lib.sh"
# shellcheck source=../../hooks/ways/embed-lib.sh
source "$EMBED_LIB"

# ── Scan a ways directory into corpus ────────────────────────────
# Args: $1=ways_dir $2=id_prefix (empty for global, "encoded-path/" for project)
# Appends to $TMPFILE, increments $count
scan_ways_dir() {
  local scan_dir="$1"
  local id_prefix="$2"

  while IFS= read -r wayfile; do
    # Extract frontmatter block
    frontmatter=$(awk 'NR==1 && /^---$/{p=1;next} p && /^---$/{exit} p{print}' "$wayfile")

    # Extract fields
    description=$(echo "$frontmatter" | awk '/^description:/{gsub(/^description: */,"");print;exit}')
    vocabulary=$(echo "$frontmatter" | awk '/^vocabulary:/{gsub(/^vocabulary: */,"");print;exit}')
    threshold=$(echo "$frontmatter" | awk '/^threshold:/{gsub(/^threshold: */,"");print;exit}')
    embed_threshold=$(echo "$frontmatter" | awk '/^embed_threshold:/{gsub(/^embed_threshold: */,"");print;exit}')

    # Skip ways without semantic fields
    [[ -z "$description" || -z "$vocabulary" ]] && continue

    # Derive id from path
    relpath="${wayfile#$scan_dir/}"
    id="${id_prefix}${relpath%/way.md}"

    # Escape JSON strings (handle quotes and backslashes)
    desc_escaped=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')
    vocab_escaped=$(printf '%s' "$vocabulary" | sed 's/\\/\\\\/g; s/"/\\"/g')
    thresh_val="${threshold:-2.0}"
    embed_thresh_val="${embed_threshold:-0.35}"

    printf '{"id":"%s","description":"%s","vocabulary":"%s","threshold":%s,"embed_threshold":%s}\n' \
      "$id" "$desc_escaped" "$vocab_escaped" "$thresh_val" "$embed_thresh_val" >> "$TMPFILE"

    count=$((count + 1))

  done < <(find "$scan_dir" -name "way.md" -type f | sort)

  # Also scan for way-*.md (future locale files)
  while IFS= read -r wayfile; do
    frontmatter=$(awk 'NR==1 && /^---$/{p=1;next} p && /^---$/{exit} p{print}' "$wayfile")
    description=$(echo "$frontmatter" | awk '/^description:/{gsub(/^description: */,"");print;exit}')
    vocabulary=$(echo "$frontmatter" | awk '/^vocabulary:/{gsub(/^vocabulary: */,"");print;exit}')
    threshold=$(echo "$frontmatter" | awk '/^threshold:/{gsub(/^threshold: */,"");print;exit}')
    embed_threshold=$(echo "$frontmatter" | awk '/^embed_threshold:/{gsub(/^embed_threshold: */,"");print;exit}')

    [[ -z "$description" || -z "$vocabulary" ]] && continue

    relpath="${wayfile#$scan_dir/}"
    id="${id_prefix}${relpath%.md}"

    desc_escaped=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')
    vocab_escaped=$(printf '%s' "$vocabulary" | sed 's/\\/\\\\/g; s/"/\\"/g')
    thresh_val="${threshold:-2.0}"
    embed_thresh_val="${embed_threshold:-0.35}"

    printf '{"id":"%s","description":"%s","vocabulary":"%s","threshold":%s,"embed_threshold":%s}\n' \
      "$id" "$desc_escaped" "$vocab_escaped" "$thresh_val" "$embed_thresh_val" >> "$TMPFILE"

    count=$((count + 1))

  done < <(find "$scan_dir" -name "way-*.md" -type f 2>/dev/null | sort)
}

# resolve_project_path provided by embed-lib.sh

# ── .ways-embed marker management ────────────────────────────────
# Marker at <project>/.claude/.ways-embed controls inclusion.
# States: "include" (default on first discovery), "disinclude" (opt-out)
check_ways_embed_marker() {
  local project_path="$1"
  local marker="${project_path}/.claude/.ways-embed"
  local ways_dir="${project_path}/.claude/ways"

  # Count semantic ways (description + vocabulary)
  local semantic_count=0
  while IFS= read -r wf; do
    local fm
    fm=$(awk 'NR==1 && /^---$/{p=1;next} p && /^---$/{exit} p{print}' "$wf")
    if echo "$fm" | grep -q '^description:' && echo "$fm" | grep -q '^vocabulary:'; then
      semantic_count=$((semantic_count + 1))
    fi
  done < <(find "$ways_dir" -name "way.md" -type f 2>/dev/null)

  if [[ -f "$marker" ]]; then
    local state
    state=$(cat "$marker" 2>/dev/null | tr -d '[:space:]')
    if [[ "$state" == "disinclude" ]]; then
      if [[ $semantic_count -gt 0 ]]; then
        log "  WARNING: ${project_path} has ${semantic_count} semantic ways but is disincluded"
      fi
      echo "disinclude"
      return
    fi
    # Any other value (include, empty, etc) → include
    echo "include"
    return
  fi

  # No marker: create one if valid semantic ways exist
  if [[ $semantic_count -gt 0 ]]; then
    # Ensure .claude/ exists (it should, since ways/ is under it)
    mkdir -p "${project_path}/.claude" 2>/dev/null
    echo "include" > "$marker" 2>/dev/null
    log "  Created .ways-embed marker: ${project_path}/.claude/.ways-embed"
    echo "include"
  else
    echo "skip"
  fi
}

# ── Main: scan global ways ───────────────────────────────────────

count=0
global_count=0
project_total=0

log "Scanning global ways: ${WAYS_DIR}"
scan_ways_dir "$WAYS_DIR" ""
global_count=$count

GLOBAL_HASH=$(content_hash "$WAYS_DIR")
log "Global ways: ${global_count} (hash: ${GLOBAL_HASH:0:16}...)"

# ── Scan project-local ways ──────────────────────────────────────
# Uses enumerate_projects from embed-lib.sh to find all projects with ways.
# For each: check marker, lint, embed if included.

MANIFEST_PROJECTS=""  # Accumulates JSON fragments for manifest

while IFS='|' read -r encoded project_path way_count sem_count; do
  ways_dir="${project_path}/.claude/ways"

  # Check .ways-embed marker
  marker_state=$(check_ways_embed_marker "$project_path")
  [[ "$marker_state" == "disinclude" || "$marker_state" == "skip" ]] && continue

  # Lint gate: project ways must pass linting to be embedded
  # GENERATE_CORPUS_RUNNING (exported above) prevents lint-ways.sh from
  # calling generate-corpus.sh again (infinite recursion).
  if [[ -x "$LINT_SCRIPT" ]]; then
    if ! bash "$LINT_SCRIPT" "$ways_dir" >/dev/null 2>&1; then
      log "  SKIP: ${project_path} — ways failed linting"
      continue
    fi
  fi

  # Scan project ways into corpus with encoded path prefix
  local_before=$count
  scan_ways_dir "$ways_dir" "${encoded}/"
  local_count=$((count - local_before))

  if [[ $local_count -gt 0 ]]; then
    project_total=$((project_total + local_count))
    local_hash=$(content_hash "$ways_dir")
    log "  ${project_path}: ${local_count} ways (hash: ${local_hash:0:16}...)"

    # Accumulate manifest entry (JSON fragment, paths escaped)
    escaped_path=$(json_escape "$project_path")
    MANIFEST_PROJECTS="${MANIFEST_PROJECTS}$(printf '    "%s": {"path": "%s", "ways_hash": "%s", "ways_count": %d}' \
      "$encoded" "$escaped_path" "$local_hash" "$local_count")
"
  fi
done < <(enumerate_projects)

# Atomic move
mv "$TMPFILE" "$OUTPUT"

log "Generated ${OUTPUT}: ${count} ways (${global_count} global, ${project_total} project)"

# ── Auto-embed ───────────────────────────────────────────────────
# If way-embed binary and model are available, add embedding vectors
if [[ -x "${XDG_WAY}/way-embed" ]]; then
  WAY_EMBED_BIN="${XDG_WAY}/way-embed"
elif [[ -x "${HOME}/.claude/bin/way-embed" ]]; then
  WAY_EMBED_BIN="${HOME}/.claude/bin/way-embed"
else
  WAY_EMBED_BIN=""
fi
MODEL_PATH="${XDG_WAY}/minilm-l6-v2.gguf"

if [[ -n "$WAY_EMBED_BIN" && -x "$WAY_EMBED_BIN" && -f "$MODEL_PATH" ]]; then
  log "Embedding model found — generating embedding vectors..."
  if "$WAY_EMBED_BIN" generate --corpus "$OUTPUT" --model "$MODEL_PATH" 2>/dev/null; then
    log "Embeddings added to ${OUTPUT}"
  else
    echo "WARNING: embedding generation failed, corpus has BM25 fields only" >&2
  fi
elif [[ ! -x "$WAY_EMBED_BIN" ]]; then
  log "Tip: install the embedding engine for 98% matching accuracy (vs 91% BM25):"
  log "  cd ~/.claude && make setup"
fi

# ── Write manifest ───────────────────────────────────────────────
# Content-addressed manifest for staleness detection (ADR-109).
# Records hashes so session-start checks can detect when regen is needed.
MANIFEST="${XDG_WAY}/embed-manifest.json"
{
  echo "{"
  printf '  "global_hash": "%s",\n' "$GLOBAL_HASH"
  printf '  "global_count": %d,\n' "$global_count"
  printf '  "total_count": %d,\n' "$count"
  echo '  "projects": {'

  # Write project entries (trim trailing comma)
  if [[ -n "$MANIFEST_PROJECTS" ]]; then
    echo "$MANIFEST_PROJECTS" | sed '/^$/d' | sed '$ ! s/$/,/'
  fi

  echo "  }"
  echo "}"
} > "$MANIFEST"

log "Manifest written: ${MANIFEST}"
