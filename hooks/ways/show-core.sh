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

# Check if ways might be stale using last fetch timestamp (no network call)
# FETCH_HEAD mtime tells us when we last fetched — if it's old, nudge the user
FETCH_HEAD="$CLAUDE_DIR/.git/FETCH_HEAD"
if [[ -f "$FETCH_HEAD" ]]; then
  FETCH_AGE_DAYS=$(( ( $(date +%s) - $(stat -c '%Y' "$FETCH_HEAD" 2>/dev/null || stat -f '%m' "$FETCH_HEAD" 2>/dev/null || echo 0) ) / 86400 ))
  if (( FETCH_AGE_DAYS >= 3 )); then
    echo ""
    echo "**Ways last synced ${FETCH_AGE_DAYS} days ago.** This session may be missing recent improvements."
    echo "Updating is highly recommended: \`git -C ~/.claude pull\`"
  fi
elif git -C "$CLAUDE_DIR" remote get-url origin &>/dev/null; then
  # Has a remote but never fetched — worth mentioning
  echo ""
  echo "**Ways have never been synced with remote.** Updating is highly recommended: \`git -C ~/.claude pull\`"
fi

# If dirty, enumerate what's changed
if [[ "$WAYS_VERSION" == *-dirty ]]; then
  dirty_files=$(git -C "$CLAUDE_DIR" status --short 2>/dev/null | awk '{print $NF}')
  dirty_count=$(echo "$dirty_files" | wc -l | tr -d ' ')
  MAX_SHOW=5

  echo ""
  if (( dirty_count >= 4 )); then
    echo "**Uncommitted local changes (${dirty_count} files)** — not tracked by git."
    echo "Other sessions won't see these. Commit to keep, or discard to match remote."
  else
    echo "**Uncommitted local changes (${dirty_count} file$([ "$dirty_count" -ne 1 ] && echo s)):**"
  fi

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
    echo "- \`${relpath}\`"
  done <<< "$sorted_files"

  if (( dirty_count > MAX_SHOW )); then
    echo "- ... and $(( dirty_count - MAX_SHOW )) more"
  fi

  if (( dirty_count < 4 )); then
    echo ""
    echo "_Run \`git -C ~/.claude status\` to review._"
  fi
fi

# Mark core as injected for this session
if [[ -n "$SESSION_ID" ]]; then
  date +%s > "/tmp/.claude-core-${SESSION_ID}"
fi
