#!/bin/bash
# Guard: exit silently if ways binary is not available.
# Source this at the top of any hook script that calls the ways binary.
#
# Usage: source "$(dirname "$0")/require-ways.sh"
#
# If the binary is missing, the script exits 0 (no error, no output).
# The SessionStart check-setup.sh hook handles the user-facing diagnostic.

WAYS_BIN="${HOME}/.claude/bin/ways"
if [[ ! -x "$WAYS_BIN" ]]; then
  exit 0
fi
