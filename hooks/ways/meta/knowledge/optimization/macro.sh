#!/bin/bash
# Macro: prepend way vocabulary health summary when optimization way fires
# Runs way-match suggest on all semantic ways and outputs a compact summary

WAY_MATCH="${HOME}/.claude/bin/way-match"

if [[ ! -x "$WAY_MATCH" ]]; then
  echo "**way-match binary not found** — build with: \`make -f tools/way-match/Makefile local\`"
  exit 0
fi

echo "## Current Way Health"
echo ""
printf "%-35s %6s %6s %6s %s\n" "Way" "Gaps" "Cover" "Unused" "Match"
printf "%-35s %6s %6s %6s %s\n" "---" "----" "-----" "------" "-----"

for wayfile in $(find "${HOME}/.claude/hooks/ways" -name "way.md" -print 2>/dev/null | sort); do
  relpath="${wayfile#${HOME}/.claude/hooks/ways/}"
  relpath="${relpath%/way.md}"

  # Check if this way has vocabulary (semantic matching)
  has_vocab=$(awk 'NR==1 && /^---$/{p=1;next} p&&/^---$/{exit} p && /^vocabulary:/{print "yes";exit}' "$wayfile")
  has_desc=$(awk 'NR==1 && /^---$/{p=1;next} p&&/^---$/{exit} p && /^description:/{print "yes";exit}' "$wayfile")

  if [[ "$has_vocab" == "yes" && "$has_desc" == "yes" ]]; then
    match_type="BM25"
  elif [[ "$has_desc" == "yes" ]]; then
    match_type="desc"
  else
    # Detect match type from frontmatter
    match_type=$(awk 'NR==1 && /^---$/{p=1;next} p&&/^---$/{exit} p && /^pattern:/{print "regex";exit} p && /^files:/{print "file";exit} p && /^commands:/{print "cmd";exit} p && /^trigger:/{print "state";exit}' "$wayfile")
    match_type="${match_type:-regex}"
  fi

  if [[ "$match_type" == "BM25" ]]; then
    stderr=$("$WAY_MATCH" suggest --file "$wayfile" 2>&1 >/dev/null)
    gaps=$(echo "$stderr" | sed -n 's/suggest: \([0-9]*\) gaps.*/\1/p')
    covered=$(echo "$stderr" | sed -n 's/.*, \([0-9]*\) covered.*/\1/p')
    unused=$(echo "$stderr" | sed -n 's/.*, \([0-9]*\) unused/\1/p')
    printf "%-35s %6s %6s %6s %s\n" "$relpath" "${gaps:-0}" "${covered:-0}" "${unused:-0}" "$match_type"
  else
    printf "%-35s %6s %6s %6s %s\n" "$relpath" "-" "-" "-" "$match_type"
  fi
done

# Check project-local ways too
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR/.claude/ways" ]]; then
  echo ""
  echo "### Project-local ways"
  for wayfile in $(find "$PROJECT_DIR/.claude/ways" -name "way.md" -print 2>/dev/null | sort); do
    relpath="${wayfile#$PROJECT_DIR/.claude/ways/}"
    relpath="${relpath%/way.md}"
    printf "%-35s %s\n" "$relpath" "(project-local)"
  done
fi
