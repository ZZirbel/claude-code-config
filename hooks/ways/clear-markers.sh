#!/bin/bash
# Clear way markers for fresh session
# Called on SessionStart and after compaction
#
# Reads session_id from stdin JSON input (Claude Code hook format)
# Clears ALL markers so guidance can trigger fresh in the new session

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

# Clear markers for THIS session only (other sessions stay intact)
if [[ -n "$SESSION_ID" ]]; then
  rm -f /tmp/.claude-way-*-"${SESSION_ID}" 2>/dev/null
  rm -f /tmp/.claude-core-"${SESSION_ID}" 2>/dev/null
  rm -f /tmp/.claude-tasks-active-"${SESSION_ID}" 2>/dev/null
  rm -rf /tmp/.claude-subagent-stash-"${SESSION_ID}" 2>/dev/null
  rm -f /tmp/.claude-epoch-"${SESSION_ID}" 2>/dev/null
  rm -f /tmp/.claude-check-fires-*-"${SESSION_ID}" 2>/dev/null
  rm -f /tmp/.claude-way-metrics-"${SESSION_ID}".jsonl 2>/dev/null
else
  # No session ID — legacy fallback, clear everything
  rm -f /tmp/.claude-way-* 2>/dev/null
  rm -f /tmp/.claude-core-* 2>/dev/null
  rm -f /tmp/.claude-tasks-active-* 2>/dev/null
  rm -rf /tmp/.claude-subagent-stash-* 2>/dev/null
  rm -f /tmp/.claude-epoch-* 2>/dev/null
  rm -f /tmp/.claude-check-fires-* 2>/dev/null
fi

# Log session event
mkdir -p "${HOME}/.claude/stats" 2>/dev/null
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg event "session_start" \
  --arg project "${CLAUDE_PROJECT_DIR:-$PWD}" \
  --arg session "${SESSION_ID:-unknown}" \
  '{ts:$ts,event:$event,project:$project,session:$session}' \
  >> "${HOME}/.claude/stats/events.jsonl" 2>/dev/null
