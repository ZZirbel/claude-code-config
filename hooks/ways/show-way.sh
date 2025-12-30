#!/bin/bash
# Show a "way" once per session (strips frontmatter)
# Usage: show-way.sh <way-name> <session-id>

WAY="$1"
SESSION_ID="$2"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

[[ -z "$WAY" ]] && exit 1

# Project-local takes precedence over global
if [[ -f "$PROJECT_DIR/.claude/ways/${WAY}.md" ]]; then
  WAY_FILE="$PROJECT_DIR/.claude/ways/${WAY}.md"
elif [[ -f "${HOME}/.claude/hooks/ways/${WAY}.md" ]]; then
  WAY_FILE="${HOME}/.claude/hooks/ways/${WAY}.md"
else
  exit 0
fi

# Marker: scoped to session_id
MARKER="/tmp/.claude-way-${WAY}-${SESSION_ID:-$(date +%Y%m%d)}"

if [[ ! -f "$MARKER" ]]; then
  # Output content, stripping YAML frontmatter if present
  awk 'BEGIN{fm=0} /^---$/{fm++; next} fm!=1' "$WAY_FILE"
  touch "$MARKER"
fi
