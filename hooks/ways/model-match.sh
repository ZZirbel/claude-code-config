#!/bin/bash
# Model-based way classification using "phone a friend"
# Spawns minimal claude -p subprocess for yes/no classification
#
# Usage: model-match.sh "user prompt" "way description"
# Returns exit 0 if way should fire, exit 1 otherwise
#
# Uses existing Claude Code subscription - no separate API key needed.

PROMPT="$1"
DESCRIPTION="$2"

[[ -z "$PROMPT" || -z "$DESCRIPTION" ]] && exit 1

# Minimal claude invocation: single turn, no tools, no session persistence
RESULT=$(timeout 15 claude -p --max-turns 1 --tools "" --no-session-persistence \
  "Does this user message relate to: ${DESCRIPTION}?

User message: ${PROMPT}

Answer only 'yes' or 'no':" 2>/dev/null)

if echo "$RESULT" | grep -qi "yes"; then
  exit 0
else
  exit 1
fi
