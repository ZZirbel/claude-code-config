#!/bin/bash
# Check bash commands and descriptions, trigger relevant ways

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
DESC=$(echo "$INPUT" | jq -r '.tool_input.description // empty' | tr '[:upper:]' '[:lower:]')
CONF="${HOME}/.claude/hooks/ways/keywords.conf"

# Command-specific triggers (exact patterns)
[[ "$CMD" =~ ^gh\ |^gh$ ]] && ~/.claude/hooks/ways/show-way.sh github
[[ "$CMD" =~ git\ commit ]] && ~/.claude/hooks/ways/show-way.sh commits
[[ "$CMD" =~ \.patch|\.diff|git\ apply|git\ diff.*\> ]] && ~/.claude/hooks/ways/show-way.sh patches

# Description keyword matching (from config)
if [[ -n "$DESC" ]]; then
  while IFS=: read -r way pattern; do
    [[ "$way" =~ ^#.*$ || -z "$way" ]] && continue
    if [[ "$DESC" =~ $pattern ]]; then
      ~/.claude/hooks/ways/show-way.sh "$way"
    fi
  done < "$CONF"
fi
