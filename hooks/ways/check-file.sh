#!/bin/bash
# Check file operations and trigger relevant ways

# Read stdin once
INPUT=$(cat)
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Check patterns and trigger ways
if [[ "$FP" =~ docs/adr/.*\.md$ ]]; then
  ${HOME}/.claude/hooks/ways/show-way.sh adr
fi

if [[ "$FP" =~ \.(patch|diff)$ ]]; then
  ${HOME}/.claude/hooks/ways/show-way.sh patches
fi

if [[ "$FP" =~ \.claude/todo-.*\.md$ ]]; then
  ${HOME}/.claude/hooks/ways/show-way.sh tracking
fi
