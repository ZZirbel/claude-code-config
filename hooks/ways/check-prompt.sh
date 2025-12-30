#!/bin/bash
# Check user prompts for keywords from way frontmatter

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' | tr '[:upper:]' '[:lower:]')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(echo "$INPUT" | jq -r '.cwd // empty')}"

# Scan ways in a directory for keyword matches
scan_ways() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return

  for wayfile in "$dir"/*.md; do
    [[ ! -f "$wayfile" ]] && continue
    [[ "$(basename "$wayfile")" == "core.md" ]] && continue

    # Extract keywords from frontmatter
    keywords=$(awk '/^---$/{p=!p; next} p && /^keywords:/' "$wayfile" | sed 's/^keywords: *//')
    [[ -z "$keywords" ]] && continue

    # Check if prompt matches keywords
    if [[ "$PROMPT" =~ $keywords ]]; then
      wayname=$(basename "$wayfile" .md)
      ~/.claude/hooks/ways/show-way.sh "$wayname" "$SESSION_ID"
    fi
  done
}

# Scan project-local first, then global
scan_ways "$PROJECT_DIR/.claude/ways"
scan_ways "${HOME}/.claude/hooks/ways"
