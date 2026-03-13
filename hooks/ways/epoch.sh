#!/bin/bash
# Epoch counter — increments on every hook event within a session.
# Source this file; it sets EPOCH to the current count.
#
# Usage:
#   source "${HOME}/.claude/hooks/ways/epoch.sh"
#   bump_epoch "$SESSION_ID"
#   # now $EPOCH is set
#
# When a way fires, stamp the epoch:
#   stamp_way_epoch "$WAY_MARKER_NAME" "$SESSION_ID"
#
# When a check fires, read the distance:
#   get_epoch_distance "$WAY_MARKER_NAME" "$SESSION_ID"
#   # now $EPOCH_DISTANCE is set

bump_epoch() {
  local session_id="$1"
  local counter_file="/tmp/.claude-epoch-${session_id}"
  EPOCH=$(( $(cat "$counter_file" 2>/dev/null || echo 0) + 1 ))
  echo "$EPOCH" > "$counter_file"
}

stamp_way_epoch() {
  local way_marker_name="$1"
  local session_id="$2"
  echo "$EPOCH" > "/tmp/.claude-way-epoch-${way_marker_name}-${session_id}"
}

get_epoch_distance() {
  local way_marker_name="$1"
  local session_id="$2"
  local way_epoch=$(cat "/tmp/.claude-way-epoch-${way_marker_name}-${session_id}" 2>/dev/null || echo 0)
  EPOCH_DISTANCE=$(( EPOCH - way_epoch ))
}
