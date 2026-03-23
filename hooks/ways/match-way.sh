#!/bin/bash
# Shared matching logic for ways — sourced by check-prompt.sh and check-task-pre.sh
#
# Usage:
#   source "${WAYS_DIR}/match-way.sh"
#   detect_semantic_engine
#   match_way_prompt "$prompt" "$pattern" "$description" "$vocabulary" "$threshold"
#     → returns 0 (match) or 1 (no match)

WAYS_DIR="${WAYS_DIR:-${HOME}/.claude/hooks/ways}"

# Check `when:` preconditions — deterministic gate before any matching.
# Returns 0 if all preconditions are met (or no when: block), 1 if any fail.
# Args: $1=frontmatter (raw text)
# Requires: PROJECT_DIR to be set by the calling scanner
check_when_preconditions() {
  local frontmatter="$1"

  # Extract when: block fields (indented under when:)
  local when_project
  when_project=$(echo "$frontmatter" | awk '/^when:/{found=1;next} found && /^  project:/{gsub(/^  project: */,"");print;exit} found && /^[^ ]/{exit}')

  # No when: block → no gate → allow
  [[ -z "$when_project" ]] && return 0

  # when.project: check if current project dir matches
  if [[ -n "$when_project" ]]; then
    # Expand ~ to $HOME for comparison
    local expanded_project="${when_project/#\~/$HOME}"
    local resolved_project
    resolved_project=$(cd "$expanded_project" 2>/dev/null && pwd -P || echo "$expanded_project")
    local resolved_current
    resolved_current=$(cd "${PROJECT_DIR:-.}" 2>/dev/null && pwd -P || echo "${PROJECT_DIR:-.}")

    [[ "$resolved_current" != "$resolved_project" ]] && return 1
  fi

  return 0
}

# Detect semantic matcher: embedding → BM25 binary → gzip NCD → none
# Sets: SEMANTIC_ENGINE, WAY_MATCH_BIN, WAY_EMBED_BIN, MODEL_PATH, CORPUS_PATH, EMBED_CACHE
detect_semantic_engine() {
  WAY_EMBED_BIN="${HOME}/.claude/bin/way-embed"
  WAY_MATCH_BIN="${HOME}/.claude/bin/way-match"
  MODEL_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/claude-ways/user/minilm-l6-v2.gguf"
  CORPUS_PATH=""
  EMBED_CACHE=""
  local corpus_file="${WAYS_DIR}/ways-corpus.jsonl"
  [[ -f "$corpus_file" ]] && CORPUS_PATH="$corpus_file"

  if [[ -x "$WAY_EMBED_BIN" && -f "$MODEL_PATH" && -n "$CORPUS_PATH" ]]; then
    SEMANTIC_ENGINE="embedding"
    # XDG-compliant project-scoped cache for batch results
    local cache_base="${XDG_CACHE_HOME:-$HOME/.cache}/claude-ways/projects"
    local encoded_project
    encoded_project=$(echo "${PROJECT_DIR:-$PWD}" | tr '/' '-')
    local cache_dir="${cache_base}/${encoded_project}"
    mkdir -p "$cache_dir" 2>/dev/null
    EMBED_CACHE="${cache_dir}/embed-results.tsv"
    # Clean up stale cache from prior runs
    rm -f "$EMBED_CACHE" 2>/dev/null
  elif [[ -x "$WAY_MATCH_BIN" ]]; then
    SEMANTIC_ENGINE="bm25"
  elif command -v gzip >/dev/null 2>&1 && command -v bc >/dev/null 2>&1; then
    SEMANTIC_ENGINE="ncd"
  else
    SEMANTIC_ENGINE="none"
  fi
}

# Additive matching: pattern OR semantic (either channel can fire)
# Args: $1=prompt $2=pattern $3=description $4=vocabulary $5=threshold $6=way_id
# Sets: MATCH_CHANNEL ("keyword" or "semantic") on match
match_way_prompt() {
  local prompt="$1" pattern="$2" description="$3" vocabulary="$4" threshold="$5" way_id="$6"
  MATCH_CHANNEL=""

  # Channel 1: Regex pattern match
  if [[ -n "$pattern" && "$prompt" =~ $pattern ]]; then
    MATCH_CHANNEL="keyword"
    return 0
  fi

  # Channel 2: Semantic match
  case "$SEMANTIC_ENGINE" in
    embedding)
      # Lazy batch: run once per prompt eval, cache for subsequent lookups.
      # way-embed match scores ALL corpus ways in one call (~22ms total).
      if [[ -n "$EMBED_CACHE" && ! -f "$EMBED_CACHE" ]]; then
        "$WAY_EMBED_BIN" match \
            --corpus "$CORPUS_PATH" \
            --model "$MODEL_PATH" \
            --query "$prompt" > "$EMBED_CACHE" 2>/dev/null
      fi
      # Look up this way's id in cached batch results
      if [[ -n "$way_id" && -f "$EMBED_CACHE" ]] && grep -q "^${way_id}	" "$EMBED_CACHE"; then
        MATCH_CHANNEL="semantic"
        return 0
      fi
      ;;
    bm25)
      if [[ -n "$description" && -n "$vocabulary" ]]; then
        local corpus_args=()
        [[ -n "$CORPUS_PATH" ]] && corpus_args=(--corpus "$CORPUS_PATH")
        if "$WAY_MATCH_BIN" pair \
            --description "$description" \
            --vocabulary "$vocabulary" \
            --query "$prompt" \
            --threshold "${threshold:-2.0}" \
            "${corpus_args[@]}" 2>/dev/null; then
          MATCH_CHANNEL="semantic"
          return 0
        fi
      fi
      ;;
    ncd)
      if [[ -n "$description" && -n "$vocabulary" ]]; then
        # NCD fallback uses a fixed threshold (distance 0-1, lower = more similar).
        # This is intentionally NOT derived from frontmatter thresholds, which are
        # on the BM25 score scale (higher = better match). The two scales don't map
        # cleanly: BM25 threshold 2.0 ≠ NCD distance 0.58. The fixed value 0.58 was
        # tuned against the test fixture corpus for acceptable recall without false positives.
        if "${WAYS_DIR}/semantic-match.sh" "$prompt" "$description" "$vocabulary" "0.58" 2>/dev/null; then
          MATCH_CHANNEL="semantic"
          return 0
        fi
      fi
      ;;
  esac

  return 1
}
