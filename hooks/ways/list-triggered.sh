#!/bin/bash
# List ways triggered in the current session
# Usage: list-triggered.sh [session_id]
#
# If session_id provided, shows only that session's ways
# Otherwise shows all recent markers

SESSION_ID="$1"
WAYS_DIR="${HOME}/.claude/hooks/ways"

if [[ -n "$SESSION_ID" ]]; then
  pattern="/tmp/.claude-way-*-${SESSION_ID}"
else
  pattern="/tmp/.claude-way-*"
fi

markers=$(ls $pattern 2>/dev/null | sort -u)

if [[ -z "$markers" ]]; then
  echo "No ways triggered yet this session."
  exit 0
fi

echo "## Triggered Ways"
echo ""

# Track unique ways (same way can fire in multiple sessions)
declare -A seen_ways

for marker in $markers; do
  # Extract: .claude-way-{domain}-{wayname}-{uuid-with-hyphens}
  name=$(basename "$marker")
  name=${name#.claude-way-}

  # UUID is last 5 hyphen-separated segments (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx pattern)
  # Strip UUID by removing last 5 segments
  # Example: softwaredev-github-4c57c5c1-fbc7-41f0-a135-abcd1234abcd
  # We want: softwaredev-github

  # Count segments and extract way path (everything before UUID)
  IFS='-' read -ra parts <<< "$name"
  num_parts=${#parts[@]}

  # UUID has 5 parts, so way path is parts 0 to (n-6)
  if [[ $num_parts -ge 6 ]]; then
    waypath=""
    for ((i=0; i<num_parts-5; i++)); do
      [[ -n "$waypath" ]] && waypath+="-"
      waypath+="${parts[$i]}"
    done

    # Convert hyphens to slashes for path
    waypath=$(echo "$waypath" | sed 's/-/\//g')

    # Skip if already seen
    [[ -n "${seen_ways[$waypath]}" ]] && continue
    seen_ways[$waypath]=1

    # Check if way.md exists
    if [[ -f "${WAYS_DIR}/${waypath}/way.md" ]]; then
      title=$(grep -m1 '^# ' "${WAYS_DIR}/${waypath}/way.md" | sed 's/^# //')
      echo "- **${waypath}**: ${title}"
    else
      echo "- **${waypath}** _(project-local)_"
    fi
  fi
done

echo ""
echo "_Run /ways after restarting Claude Code to see fresh session_"
