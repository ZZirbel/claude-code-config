#!/bin/bash
# Detect current execution scope: agent, teammate, or subagent
# Usage: source this file, then use $CURRENT_SCOPE
#
# Detection: checks for teammate marker created by inject-subagent.sh
# Marker: /tmp/.claude-teammate-{session_id} (contains team name if available)
#
# Returns scope in CURRENT_SCOPE variable and defines scope_matches() function

detect_scope() {
  local session_id="$1"
  if [[ -f "/tmp/.claude-teammate-${session_id}" ]]; then
    echo "teammate"
  else
    echo "agent"
  fi
}

# Read team name from teammate marker (empty string if not a teammate)
detect_team() {
  local session_id="$1"
  local marker="/tmp/.claude-teammate-${session_id}"
  if [[ -f "$marker" ]]; then
    cat "$marker" 2>/dev/null
  fi
}

# Check if a way's scope field matches the current execution scope
# Usage: scope_matches "$scope_field" "$current_scope"
# Examples:
#   scope_matches "agent, subagent" "agent"     → true
#   scope_matches "agent, subagent" "teammate"  → false
#   scope_matches "agent, teammate" "teammate"  → true
#   scope_matches "teammate" "agent"            → false
scope_matches() {
  local scope_field="${1:-agent}"
  local current="$2"
  echo "$scope_field" | grep -qw "$current"
}
