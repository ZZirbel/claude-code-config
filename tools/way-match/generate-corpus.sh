#!/bin/bash
# Generate ways-corpus.jsonl from all semantic way.md files
#
# Scans for way.md files with description+vocabulary frontmatter,
# extracts fields, and emits one JSON line per way.
#
# This is an authoring-time tool. The output file is a build artifact
# committed to the repo — runtime scanners read it but never write it.
#
# Usage: generate-corpus.sh [--quiet] [ways-dir] [output-file]
#   --quiet:     suppress progress output (for use in test/lint pipelines)
#   ways-dir:    directory to scan (default: ~/.claude/hooks/ways)
#   output-file: where to write JSONL (default: <ways-dir>/ways-corpus.jsonl)

QUIET=false
[[ "${1:-}" == "--quiet" ]] && { QUIET=true; shift; }

WAYS_DIR="${1:-${HOME}/.claude/hooks/ways}"
OUTPUT="${2:-${WAYS_DIR}/ways-corpus.jsonl}"

log() { $QUIET || echo "$@" >&2; }

# Temp file for atomic write
TMPFILE="${OUTPUT}.tmp.$$"
trap 'rm -f "$TMPFILE"' EXIT

count=0

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

  # Derive id from path: hooks/ways/softwaredev/code/security/way.md → softwaredev/code/security
  relpath="${wayfile#$WAYS_DIR/}"
  id="${relpath%/way.md}"

  # Escape JSON strings (handle quotes and backslashes)
  desc_escaped=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')
  vocab_escaped=$(printf '%s' "$vocabulary" | sed 's/\\/\\\\/g; s/"/\\"/g')
  thresh_val="${threshold:-2.0}"
  embed_thresh_val="${embed_threshold:-0.35}"

  printf '{"id":"%s","description":"%s","vocabulary":"%s","threshold":%s,"embed_threshold":%s}\n' \
    "$id" "$desc_escaped" "$vocab_escaped" "$thresh_val" "$embed_thresh_val" >> "$TMPFILE"

  count=$((count + 1))

done < <(find "$WAYS_DIR" -name "way.md" -type f | sort)

# Also scan for way-*.md (future locale files)
while IFS= read -r wayfile; do
  frontmatter=$(awk 'NR==1 && /^---$/{p=1;next} p && /^---$/{exit} p{print}' "$wayfile")
  description=$(echo "$frontmatter" | awk '/^description:/{gsub(/^description: */,"");print;exit}')
  vocabulary=$(echo "$frontmatter" | awk '/^vocabulary:/{gsub(/^vocabulary: */,"");print;exit}')
  threshold=$(echo "$frontmatter" | awk '/^threshold:/{gsub(/^threshold: */,"");print;exit}')
  embed_threshold=$(echo "$frontmatter" | awk '/^embed_threshold:/{gsub(/^embed_threshold: */,"");print;exit}')

  [[ -z "$description" || -z "$vocabulary" ]] && continue

  relpath="${wayfile#$WAYS_DIR/}"
  id="${relpath%.md}"

  desc_escaped=$(printf '%s' "$description" | sed 's/\\/\\\\/g; s/"/\\"/g')
  vocab_escaped=$(printf '%s' "$vocabulary" | sed 's/\\/\\\\/g; s/"/\\"/g')
  thresh_val="${threshold:-2.0}"
  embed_thresh_val="${embed_threshold:-0.35}"

  printf '{"id":"%s","description":"%s","vocabulary":"%s","threshold":%s,"embed_threshold":%s}\n' \
    "$id" "$desc_escaped" "$vocab_escaped" "$thresh_val" "$embed_thresh_val" >> "$TMPFILE"

  count=$((count + 1))

done < <(find "$WAYS_DIR" -name "way-*.md" -type f 2>/dev/null | sort)

# Atomic move
mv "$TMPFILE" "$OUTPUT"

log "Generated ${OUTPUT}: ${count} ways"

# Auto-embed: if way-embed binary and model are available, add embedding vectors
# Check XDG cache first (downloaded), then ~/.claude/bin (built from source)
XDG_WAY="${XDG_CACHE_HOME:-$HOME/.cache}/claude-ways/user"
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
