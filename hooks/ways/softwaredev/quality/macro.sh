#!/bin/bash
# Scan for files exceeding quality thresholds
# Runs when quality way triggers - appends file list to way output

# Must be in a git repo
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

# Exclusion patterns (generated, vendor, lock files, etc.)
EXCLUDE_PATTERN='\.(lock|min\.js|min\.css|generated\.|bundle\.)|\bvendor/|\bnode_modules/|\bdist/|\bbuild/|\b__pycache__/'

THRESHOLD=500
PRIORITY_THRESHOLD=800

# Collect files over threshold
results=$(git ls-files 2>/dev/null | grep -Ev "$EXCLUDE_PATTERN" | while read -r f; do
  [[ -f "$f" && -r "$f" ]] || continue
  # Skip binary files
  file --mime "$f" 2>/dev/null | grep -q 'text/' || continue
  lines=$(wc -l < "$f" 2>/dev/null)
  ((lines > THRESHOLD)) && printf "%5d  %s\n" "$lines" "$f"
done | sort -rn)

[[ -z "$results" ]] && exit 0

# Split into priority and review
priority=$(echo "$results" | awk -v t="$PRIORITY_THRESHOLD" '$1 > t')
review=$(echo "$results" | awk -v t="$PRIORITY_THRESHOLD" '$1 <= t')

echo ""
echo "## File Length Scan"

if [[ -n "$priority" ]]; then
  echo ""
  echo "**Priority (>${PRIORITY_THRESHOLD} lines):**"
  echo '```'
  echo "$priority" | head -10
  echo '```'
fi

if [[ -n "$review" ]]; then
  echo ""
  echo "**Review (>${THRESHOLD} lines):**"
  echo '```'
  echo "$review" | head -15
  echo '```'
fi
