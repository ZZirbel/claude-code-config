#!/bin/bash
# PostToolUse: Check file operations against way frontmatter
#
# TRIGGER FLOW:
# ┌───────────────────────┐     ┌─────────────────┐     ┌──────────────┐
# │ PostToolUse:Edit/Write│────▶│ scan_ways()     │────▶│ show-way.sh  │
# │ (hook event)          │     │ for each *.md:  │     │ (idempotent) │
# └───────────────────────┘     │  if files match │     └──────────────┘
#                               └─────────────────┘
#
# Multiple ways can match a single file path - CONTEXT accumulates
# all matching way outputs. Markers prevent duplicate content.
# Output is returned as additionalContext JSON for Claude to see.

INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
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

    # Extract files pattern from frontmatter
    files=$(awk '/^---$/{p=!p; next} p && /^files:/' "$wayfile" | sed 's/^files: *//')

    # Check file path against pattern
    if [[ -n "$files" && "$FP" =~ $files ]]; then
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
