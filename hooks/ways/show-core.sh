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

# Build version status from git describe + update cache
CLAUDE_DIR="${HOME}/.claude"
# Prefer release tags (v*) over tool-specific tags (way-embed-v*, etc.)
RAW_VERSION=$(git -C "$CLAUDE_DIR" describe --tags --match 'v*' --always --dirty 2>/dev/null || echo "unknown")

# Parse git describe output into components
# Formats: "v0.1.0" (on tag), "v0.1.0-29-ge0841be" (after tag), "e0841be" (no tags), any + "-dirty"
IS_DIRTY=false
DESCRIBE="$RAW_VERSION"
if [[ "$DESCRIBE" == *-dirty ]]; then
  IS_DIRTY=true
  DESCRIBE="${DESCRIBE%-dirty}"
fi

if [[ "$DESCRIBE" =~ ^(.+)-([0-9]+)-g([0-9a-f]+)$ ]]; then
  # Between tags: tag-distance-ghash
  TAG="${BASH_REMATCH[1]}"
  DISTANCE="${BASH_REMATCH[2]}"
  HASH="${BASH_REMATCH[3]}"
  VERSION_DISPLAY="${TAG} + ${DISTANCE} commits (${HASH})"
elif [[ "$DESCRIBE" =~ ^v[0-9] ]]; then
  # Exactly on a tag
  TAG="$DESCRIBE"
  DISTANCE=0
  HASH=""
  VERSION_DISPLAY="${TAG} (release)"
else
  # No tags — bare hash
  TAG=""
  DISTANCE=""
  HASH="$DESCRIBE"
  VERSION_DISPLAY="${DESCRIBE}"
fi

$IS_DIRTY && VERSION_DISPLAY="${VERSION_DISPLAY} · dirty"

echo ""
echo "---"
echo "_Ways version: ${VERSION_DISPLAY}_"

# Read update cache written by check-config-updates.sh
# Cache persists across sessions with hourly refresh
CACHE_FILE="/tmp/.claude-config-update-state-$(id -u)"
UPSTREAM_REPO="aaronsb/claude-code-config"
if [[ -f "$CACHE_FILE" ]]; then
  CACHED_TYPE=$(sed -n 's/^type=//p' "$CACHE_FILE")
  CACHED_BEHIND=$(sed -n 's/^behind=//p' "$CACHE_FILE")
  CACHED_HAS_UPSTREAM=$(sed -n 's/^has_upstream=//p' "$CACHE_FILE")
  CACHED_FORK_OWNER=$(sed -n 's/^fork_owner=//p' "$CACHE_FILE")
  CACHED_REASON=$(sed -n 's/^reason=//p' "$CACHE_FILE")

  case "$CACHED_TYPE" in
    clone)
      if [[ "$CACHED_BEHIND" =~ ^[0-9]+$ ]] && (( CACHED_BEHIND > 0 )); then
        echo ""
        echo "**${CACHED_BEHIND} commit(s) behind origin/main.** Run: \`cd ~/.claude && git pull\`"
      fi
      ;;
    fork)
      if [[ "$CACHED_BEHIND" =~ ^[0-9]+$ ]] && (( CACHED_BEHIND > 0 )); then
        echo ""
        if [[ "$CACHED_HAS_UPSTREAM" == "true" ]]; then
          echo "**Behind ${UPSTREAM_REPO}.** Run: \`cd ~/.claude && git fetch upstream && git merge upstream/main\`"
        else
          echo "**Behind ${UPSTREAM_REPO}.** First add upstream, then sync:"
          echo "\`git -C ~/.claude remote add upstream https://github.com/${UPSTREAM_REPO}\`"
          echo "\`cd ~/.claude && git fetch upstream && git merge upstream/main\`"
        fi
      elif [[ -n "$CACHED_FORK_OWNER" ]]; then
        echo ""
        echo "_Fork: ${CACHED_FORK_OWNER}/claude-code-config (up to date)_"
      fi
      ;;
    renamed_clone)
      if [[ "$CACHED_BEHIND" =~ ^[0-9]+$ ]] && (( CACHED_BEHIND > 0 )); then
        echo ""
        if [[ "$CACHED_HAS_UPSTREAM" == "true" ]]; then
          echo "**Behind ${UPSTREAM_REPO}.** Run: \`cd ~/.claude && git fetch upstream && git merge upstream/main\`"
        else
          echo "**Behind ${UPSTREAM_REPO}.** First add upstream:"
          echo "\`git -C ~/.claude remote add upstream https://github.com/${UPSTREAM_REPO}\`"
          echo "\`cd ~/.claude && git fetch upstream && git merge upstream/main\`"
        fi
      fi
      ;;
    plugin)
      INSTALLED=$(sed -n 's/^installed=//p' "$CACHE_FILE")
      LATEST=$(sed -n 's/^latest=//p' "$CACHE_FILE")
      if [[ "$CACHED_BEHIND" =~ ^[0-9]+$ ]] && (( CACHED_BEHIND > 0 )); then
        echo ""
        echo "**Plugin update available (v${INSTALLED} -> v${LATEST}).** Run: \`/plugin update disciplined-methodology\`"
      fi
      ;;
    gh_unavailable)
      # Surface gh issue — cache refreshes hourly so this won't spam
      if [[ -n "$CACHED_REASON" ]]; then
        echo ""
        echo "_Update check skipped: ${CACHED_REASON}_"
      fi
      ;;
  esac
fi

# If dirty, enumerate what's changed
if $IS_DIRTY; then
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
