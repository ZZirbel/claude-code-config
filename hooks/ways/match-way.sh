#!/bin/bash
# Shared matching logic for ways — sourced by check-prompt.sh and check-task-pre.sh
#
# Usage:
#   source "${WAYS_DIR}/match-way.sh"
#   detect_semantic_engine
#   match_way_prompt "$prompt" "$pattern" "$description" "$vocabulary" "$threshold"
#     → returns 0 (match) or 1 (no match)

WAYS_DIR="${WAYS_DIR:-${HOME}/.claude/hooks/ways}"

# Detect semantic matcher: BM25 binary → gzip NCD → none
# Sets: SEMANTIC_ENGINE, WAY_MATCH_BIN
detect_semantic_engine() {
  WAY_MATCH_BIN="${HOME}/.claude/bin/way-match"
  if [[ -x "$WAY_MATCH_BIN" ]]; then
    SEMANTIC_ENGINE="bm25"
  elif command -v gzip >/dev/null 2>&1 && command -v bc >/dev/null 2>&1; then
    SEMANTIC_ENGINE="ncd"
  else
    SEMANTIC_ENGINE="none"
  fi
}

# Additive matching: pattern OR semantic (either channel can fire)
# Args: $1=prompt $2=pattern $3=description $4=vocabulary $5=threshold
match_way_prompt() {
  local prompt="$1" pattern="$2" description="$3" vocabulary="$4" threshold="$5"

  # Channel 1: Regex pattern match
  if [[ -n "$pattern" && "$prompt" =~ $pattern ]]; then
    return 0
  fi

  # Channel 2: Semantic match (only if description+vocabulary present)
  if [[ -n "$description" && -n "$vocabulary" ]]; then
    case "$SEMANTIC_ENGINE" in
      bm25)
        if "$WAY_MATCH_BIN" pair \
            --description "$description" \
            --vocabulary "$vocabulary" \
            --query "$prompt" \
            --threshold "${threshold:-2.0}" 2>/dev/null; then
          return 0
        fi
        ;;
      ncd)
        # NCD fallback uses a fixed threshold (distance 0-1, lower = more similar).
        # This is intentionally NOT derived from frontmatter thresholds, which are
        # on the BM25 score scale (higher = better match). The two scales don't map
        # cleanly: BM25 threshold 2.0 ≠ NCD distance 0.58. The fixed value 0.58 was
        # tuned against the test fixture corpus for acceptable recall without false positives.
        if "${WAYS_DIR}/semantic-match.sh" "$prompt" "$description" "$vocabulary" "0.58" 2>/dev/null; then
          return 0
        fi
        ;;
    esac
  fi

  return 1
}
