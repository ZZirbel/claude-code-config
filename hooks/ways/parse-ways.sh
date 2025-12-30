#!/bin/bash
# Parse all way files and check for keyword matches
# Usage: parse-ways.sh <text-to-match> <session-id> [ways-dir...]

TEXT="$1"
SESSION_ID="$2"
shift 2
WAYS_DIRS=("$@")

# Default directories if none provided
if [[ ${#WAYS_DIRS[@]} -eq 0 ]]; then
  WAYS_DIRS=("${HOME}/.claude/hooks/ways")
fi

# For each ways directory
for dir in "${WAYS_DIRS[@]}"; do
  [[ ! -d "$dir" ]] && continue

  # For each markdown file
  for wayfile in "$dir"/*.md; do
    [[ ! -f "$wayfile" ]] && continue
    [[ "$(basename "$wayfile")" == "core.md" ]] && continue

    # Extract keywords from frontmatter
    keywords=$(awk '/^---$/{p=!p; next} p && /^keywords:/' "$wayfile" | sed 's/^keywords: *//')

    [[ -z "$keywords" ]] && continue

    # Check if text matches keywords
    if [[ "$TEXT" =~ $keywords ]]; then
      wayname=$(basename "$wayfile" .md)
      ~/.claude/hooks/ways/show-way.sh "$wayname" "$SESSION_ID"
    fi
  done
done
