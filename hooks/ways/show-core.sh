#!/bin/bash
# Show core.md with dynamic table from macro
# Runs macro.sh first, then outputs static content from core.md
#
# Creates a core marker so check-state.sh can detect if core guidance
# was lost (e.g., plan mode context clear) and re-inject it.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
WAYS_DIR="${HOME}/.claude/hooks/ways"

# Run macro to generate dynamic table
"${WAYS_DIR}/macro.sh"

# Output static content (skip frontmatter)
awk 'BEGIN{fm=0} /^---$/{fm++; next} fm!=1' "${WAYS_DIR}/core.md"

# Append ways version: tag (if any) + commit + clean/dirty state
CLAUDE_DIR="${HOME}/.claude"
WAYS_VERSION=$(git -C "$CLAUDE_DIR" describe --tags --always --dirty 2>/dev/null || echo "unknown")
echo ""
echo "---"
echo "_Ways version: ${WAYS_VERSION}_"

# If dirty, enumerate what's changed
if [[ "$WAYS_VERSION" == *-dirty ]]; then
  # Get dirty files sorted by most recently modified
  dirty_files=$(git -C "$CLAUDE_DIR" status --short 2>/dev/null | awk '{print $NF}')
  dirty_count=$(echo "$dirty_files" | wc -l | tr -d ' ')
  MAX_SHOW=5

  echo ""
  echo "_Uncommitted changes (${dirty_count} file$([ "$dirty_count" -ne 1 ] && echo s)):_"

  # Sort by mtime descending (most recently changed first)
  sorted_files=$(while IFS= read -r f; do
    filepath="$CLAUDE_DIR/$f"
    if [[ -e "$filepath" ]]; then
      stat -c '%Y %n' "$filepath" 2>/dev/null || stat -f '%m %N' "$filepath" 2>/dev/null
    fi
  done <<< "$dirty_files" | sort -rn | head -"$MAX_SHOW" | awk '{print $2}')

  while IFS= read -r fullpath; do
    [[ -z "$fullpath" ]] && continue
    relpath="${fullpath#$CLAUDE_DIR/}"
    echo "_  ${relpath}_"
  done <<< "$sorted_files"

  if (( dirty_count > MAX_SHOW )); then
    echo "_  ... and $(( dirty_count - MAX_SHOW )) more_"
  fi
  echo "_Run \`git -C ~/.claude status --short\` to list all._"
fi

# Mark core as injected for this session
if [[ -n "$SESSION_ID" ]]; then
  date +%s > "/tmp/.claude-core-${SESSION_ID}"
fi
