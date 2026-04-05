#!/bin/bash
# Per-user sessions root — shared by all hook scripts.
# Must agree with session::sessions_root() in the ways binary.
#
# Usage: source this file, then use $SESSIONS_ROOT
#   source "$(dirname "$0")/sessions-root.sh"

if [[ -n "$XDG_RUNTIME_DIR" ]]; then
  SESSIONS_ROOT="${XDG_RUNTIME_DIR}/claude-sessions"
else
  SESSIONS_ROOT="/tmp/.claude-sessions-$(id -u)"
fi
