#!/bin/bash
# State-based way trigger evaluator
# Scans ways for `trigger:` declarations and evaluates conditions
#
# Supported triggers:
#   trigger: context-threshold
#   threshold: 90                 # percentage (0-100)
#
#   trigger: file-exists
#   path: .claude/todo-*.md       # glob pattern relative to project
#
#   trigger: session-start        # fires once at session begin
#
# Runs every UserPromptSubmit, evaluates conditions, fires matching ways.
# Uses standard marker system for once-per-session gating.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(echo "$INPUT" | jq -r '.cwd // empty')}"

WAYS_DIR="${HOME}/.claude/hooks/ways"
CONTEXT=""

# Get transcript size since last compaction (bytes after last summary line)
get_transcript_size() {
  [[ ! -f "$TRANSCRIPT" ]] && echo 0 && return

  # Find last summary line (compaction marker)
  local last_summary=$(grep -n '"type":"summary"' "$TRANSCRIPT" 2>/dev/null | tail -1 | cut -d: -f1)

  if [[ -n "$last_summary" ]]; then
    # Count bytes from last summary to end
    tail -n +$last_summary "$TRANSCRIPT" | wc -c
  else
    # No summary found, use full file
    wc -c < "$TRANSCRIPT"
  fi
}

# Evaluate a trigger condition
# Returns 0 if condition met, 1 otherwise
evaluate_trigger() {
  local trigger="$1"
  local wayfile="$2"

  case "$trigger" in
    context-threshold)
      local threshold=$(awk '/^threshold:/' "$wayfile" | sed 's/^threshold: *//')
      threshold=${threshold:-90}

      # ~4 chars/token, ~155K window = 620K chars
      # threshold% of 620K
      local limit=$((620000 * threshold / 100))
      local size=$(get_transcript_size)

      [[ $size -gt $limit ]]
      return $?
      ;;

    file-exists)
      local pattern=$(awk '/^path:/' "$wayfile" | sed 's/^path: *//')
      [[ -z "$pattern" ]] && return 1

      # Expand glob relative to project dir
      local matches=$(ls "${PROJECT_DIR}"/${pattern} 2>/dev/null | head -1)
      [[ -n "$matches" ]]
      return $?
      ;;

    session-start)
      # Always true on first eval - marker handles once-per-session
      return 0
      ;;

    *)
      # Unknown trigger type
      return 1
      ;;
  esac
}

# Scan ways for state triggers
scan_state_triggers() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return

  while IFS= read -r -d '' wayfile; do
    # Extract way path relative to ways dir
    local waypath="${wayfile#$dir/}"
    waypath="${waypath%/way.md}"

    # Check for trigger: field in frontmatter
    local trigger=$(awk 'NR==1 && /^---$/{p=1; next} p && /^---$/{exit} p && /^trigger:/' "$wayfile" | sed 's/^trigger: *//')

    [[ -z "$trigger" ]] && continue

    # Evaluate the trigger condition
    if evaluate_trigger "$trigger" "$wayfile"; then
      # Condition met - fire the way (show-way.sh handles marker)
      local output=$("${WAYS_DIR}/show-way.sh" "$waypath" "$SESSION_ID")
      [[ -n "$output" ]] && CONTEXT+="$output"$'\n\n'
    fi

  done < <(find "$dir" -name "way.md" -print0 2>/dev/null)
}

# Scan project-local first, then global
scan_state_triggers "$PROJECT_DIR/.claude/ways"
scan_state_triggers "${WAYS_DIR}"

# Output accumulated context
if [[ -n "$CONTEXT" ]]; then
  jq -n --arg ctx "${CONTEXT%$'\n\n'}" '{"additionalContext": $ctx}'
fi
