#!/bin/bash
# Show a "check" with epoch-distance-aware scoring and fire decay.
# Usage: show-check.sh <way-path> <session-id> <trigger> <match-score>
#
# Unlike ways (fire once per session), checks fire multiple times with
# a scoring curve that modulates based on:
#   - Epoch distance from parent way (further = more valuable to re-anchor)
#   - Fire count this session (more fires = diminishing returns)
#
# SCORING:
#   effective_score = match_score × distance_factor × decay_factor
#   distance_factor = ln(epoch_distance + 1) + 1
#   decay_factor    = 1 / (fire_count + 1)
#
# If parent way has NOT fired, inject way alongside check (distance = max).
#
# STATE:
#   /tmp/.claude-check-fires-{checkname}-{session_id}  — fire count
#   /tmp/.claude-way-epoch-{wayname}-{session_id}      — epoch when way fired
#   /tmp/.claude-epoch-{session_id}                    — current epoch

WAY="$1"
SESSION_ID="$2"
TRIGGER="${3:-unknown}"
MATCH_SCORE="${4:-0}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
WAYS_DIR="${HOME}/.claude/hooks/ways"

# Detect execution scope
source "${WAYS_DIR}/detect-scope.sh"
SCOPE=$(detect_scope "$SESSION_ID")
TEAM=$(detect_team "$SESSION_ID")

[[ -z "$WAY" ]] && exit 1

# Check if domain is disabled
WAYS_CONFIG="${HOME}/.claude/ways.json"
DOMAIN="${WAY%%/*}"
if [[ -f "$WAYS_CONFIG" ]]; then
  if jq -e --arg d "$DOMAIN" '.disabled | index($d) != null' "$WAYS_CONFIG" >/dev/null 2>&1; then
    exit 0
  fi
fi

# Sanitize way path for marker filenames
WAY_MARKER_NAME=$(echo "$WAY" | tr '/' '-')

# Find *.check.md — project-local takes precedence
_find_check_file() {
  local dir="$1"
  for f in "$dir"/*.check.md; do
    [[ -f "$f" ]] && echo "$f" && return 0
  done
  return 1
}

CHECK_FILE=""
WAY_DIR=""
IS_PROJECT_LOCAL=false
if [[ -d "$PROJECT_DIR/.claude/ways/${WAY}" ]]; then
  CHECK_FILE=$(_find_check_file "$PROJECT_DIR/.claude/ways/${WAY}" 2>/dev/null || true)
  [[ -n "$CHECK_FILE" ]] && { WAY_DIR="$PROJECT_DIR/.claude/ways/${WAY}"; IS_PROJECT_LOCAL=true; }
fi
if [[ -z "$CHECK_FILE" && -d "${WAYS_DIR}/${WAY}" ]]; then
  CHECK_FILE=$(_find_check_file "${WAYS_DIR}/${WAY}" 2>/dev/null || true)
  [[ -n "$CHECK_FILE" ]] && WAY_DIR="${WAYS_DIR}/${WAY}"
fi

[[ -z "$CHECK_FILE" ]] && exit 0

# --- Epoch distance ---
source "${WAYS_DIR}/epoch.sh"
CURRENT_EPOCH=$(cat "/tmp/.claude-epoch-${SESSION_ID}" 2>/dev/null || echo 0)

WAY_MARKER="/tmp/.claude-way-${WAY_MARKER_NAME}-${SESSION_ID}"
WAY_HAS_FIRED=false
EPOCH_DISTANCE=30  # default: way hasn't fired — cap at 30 to prevent score explosion

if [[ -f "$WAY_MARKER" ]]; then
  WAY_HAS_FIRED=true
  WAY_EPOCH=$(cat "/tmp/.claude-way-epoch-${WAY_MARKER_NAME}-${SESSION_ID}" 2>/dev/null || echo 0)
  EPOCH_DISTANCE=$(( CURRENT_EPOCH - WAY_EPOCH ))
  [[ $EPOCH_DISTANCE -lt 0 ]] && EPOCH_DISTANCE=0
  # Cap distance to keep the curve bounded
  [[ $EPOCH_DISTANCE -gt 30 ]] && EPOCH_DISTANCE=30
fi

# --- Fire count ---
FIRE_COUNT_FILE="/tmp/.claude-check-fires-${WAY_MARKER_NAME}-${SESSION_ID}"
FIRE_COUNT=$(cat "$FIRE_COUNT_FILE" 2>/dev/null || echo 0)

# --- Scoring curve ---
EFFECTIVE_SCORE=$(awk "BEGIN {
  dist_factor = log(${EPOCH_DISTANCE} + 1) + 1
  decay_factor = 1.0 / (${FIRE_COUNT} + 1)
  printf \"%.2f\", ${MATCH_SCORE} * dist_factor * decay_factor
}")

# Extract threshold from check frontmatter
THRESHOLD=$(awk '/^---$/{p=!p; next} p && /^threshold:/{gsub(/^threshold: */, ""); print; exit}' "$CHECK_FILE")
THRESHOLD="${THRESHOLD:-2.0}"

# Does the effective score meet threshold?
FIRES=$(awk "BEGIN { print (${EFFECTIVE_SCORE} >= ${THRESHOLD}) ? 1 : 0 }")
[[ "$FIRES" -ne 1 ]] && exit 0

# --- Output ---
OUTPUT=""

# If way hasn't fired, pull it in alongside the check
if ! $WAY_HAS_FIRED; then
  WAY_OUTPUT=$("${WAYS_DIR}/show-way.sh" "$WAY" "$SESSION_ID" "check-pull")
  if [[ -n "$WAY_OUTPUT" ]]; then
    OUTPUT+="$WAY_OUTPUT"
    OUTPUT+=$'\n\n'
  fi
fi

# Extract anchor and check sections from check.md
# Anchor is included when epoch distance >= 5 (way is getting cold)
INCLUDE_ANCHOR=$(awk "BEGIN { print (${EPOCH_DISTANCE} >= 5) ? 1 : 0 }")

if [[ "$INCLUDE_ANCHOR" -eq 1 ]]; then
  # Full output: anchor + check sections (strip frontmatter)
  OUTPUT+=$(awk '
    BEGIN { fm=0; section="" }
    /^---$/ { fm++; next }
    fm == 1 { next }  # skip frontmatter
    /^## anchor/ { section="anchor"; next }
    /^## check/ { section="check"; next }
    /^## / { section="other"; next }
    section == "anchor" || section == "check" { print }
  ' "$CHECK_FILE")
else
  # Light output: check section only (strip frontmatter + anchor)
  OUTPUT+=$(awk '
    BEGIN { fm=0; section="" }
    /^---$/ { fm++; next }
    fm == 1 { next }
    /^## check/ { section="check"; next }
    /^## / { section="other" }
    section == "check" { print }
  ' "$CHECK_FILE")
fi

# Emit output
echo "$OUTPUT"

# Update fire count
echo $(( FIRE_COUNT + 1 )) > "$FIRE_COUNT_FILE"

# Log event
ANCHORED="false"
[[ "$INCLUDE_ANCHOR" -eq 1 ]] && ANCHORED="true"
"${WAYS_DIR}/log-event.sh" \
  event=check_fired \
  check="$WAY" \
  domain="$DOMAIN" \
  trigger="$TRIGGER" \
  epoch="$CURRENT_EPOCH" \
  way_epoch="${WAY_EPOCH:-0}" \
  distance="$EPOCH_DISTANCE" \
  fire_count="$((FIRE_COUNT + 1))" \
  match_score="$MATCH_SCORE" \
  effective_score="$EFFECTIVE_SCORE" \
  anchored="$ANCHORED" \
  scope="$SCOPE" \
  project="$PROJECT_DIR" \
  session="$SESSION_ID"
