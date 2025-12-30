#!/bin/bash
# PostToolUse: Check bash commands against way frontmatter

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
DESC=$(echo "$INPUT" | jq -r '.tool_input.description // empty' | tr '[:upper:]' '[:lower:]')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(echo "$INPUT" | jq -r '.cwd // empty')}"

CONTEXT=""

# Scan ways in a directory
scan_ways() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return

  for wayfile in "$dir"/*.md; do
    [[ ! -f "$wayfile" ]] && continue
    [[ "$(basename "$wayfile")" == "core.md" ]] && continue

    wayname=$(basename "$wayfile" .md)

    # Extract frontmatter fields
    commands=$(awk '/^---$/{p=!p; next} p && /^commands:/' "$wayfile" | sed 's/^commands: *//')
    keywords=$(awk '/^---$/{p=!p; next} p && /^keywords:/' "$wayfile" | sed 's/^keywords: *//')

    # Check command patterns
    if [[ -n "$commands" && "$CMD" =~ $commands ]]; then
      CONTEXT+=$(~/.claude/hooks/ways/show-way.sh "$wayname" "$SESSION_ID")
    fi

    # Check description against keywords
    if [[ -n "$DESC" && -n "$keywords" && "$DESC" =~ $keywords ]]; then
      CONTEXT+=$(~/.claude/hooks/ways/show-way.sh "$wayname" "$SESSION_ID")
    fi
  done
}

# Scan project-local first, then global
scan_ways "$PROJECT_DIR/.claude/ways"
scan_ways "${HOME}/.claude/hooks/ways"

# Output JSON with additionalContext if we have any
if [[ -n "$CONTEXT" ]]; then
  jq -n --arg ctx "$CONTEXT" '{
    "hookSpecificOutput": {
      "hookEventName": "PostToolUse",
      "additionalContext": $ctx
    }
  }'
fi
