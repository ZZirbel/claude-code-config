#!/bin/bash
# Clear way markers for fresh session
# Called on SessionStart and after compaction
#
# Reads session_id from stdin JSON input (Claude Code hook format)
# Clears this session's state directory only — other sessions stay intact

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Clear session state
if [[ -n "$SESSION_ID" ]]; then
  rm -rf "/tmp/.claude-sessions/${SESSION_ID}" 2>/dev/null
else
  # No session ID — legacy fallback, clear everything
  rm -rf /tmp/.claude-sessions 2>/dev/null
fi

# Log session event
mkdir -p "${HOME}/.claude/stats" 2>/dev/null
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg event "session_start" \
  --arg project "${CLAUDE_PROJECT_DIR:-$PWD}" \
  --arg session "${SESSION_ID:-unknown}" \
  '{ts:$ts,event:$event,project:$project,session:$session}' \
  >> "${HOME}/.claude/stats/events.jsonl" 2>/dev/null
