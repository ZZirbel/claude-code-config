#!/bin/bash
# Governance Operator — query provenance traceability for ways
#
# Usage:
#   governance.sh                         Coverage report (default)
#   governance.sh --trace WAY             End-to-end trace for a way
#   governance.sh --control PATTERN       Which ways implement a control
#   governance.sh --policy PATTERN        Which ways derive from a policy
#   governance.sh --gaps                  List ways without provenance
#   governance.sh --stale [DAYS]          Ways with stale verified dates (default: 90)
#   governance.sh --active                Cross-reference with way firing stats
#   governance.sh --json                  Machine-readable output (any mode)
#
# The governance operator wraps provenance-scan.py and provenance-verify.sh
# with auditor-friendly query modes. It generates a fresh manifest on each
# invocation unless --manifest is provided.

set -euo pipefail

# Resolve symlinks so SCRIPT_DIR always points to governance/
SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
SCANNER="${SCRIPT_DIR}/provenance-scan.py"
VERIFIER="${SCRIPT_DIR}/provenance-verify.sh"
STATS_FILE="${HOME}/.claude/stats/events.jsonl"

# Check dependencies
for cmd in jq python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not installed." >&2
    exit 1
  fi
done

# Parse args
MODE="report"
TRACE_WAY=""
CONTROL_PATTERN=""
POLICY_PATTERN=""
STALE_DAYS=90
JSON_OUT=false
MANIFEST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace)     MODE="trace"; [[ $# -lt 2 ]] && { echo "Error: --trace requires a way name (e.g., softwaredev/commits)" >&2; exit 1; }; TRACE_WAY="$2"; shift 2 ;;
    --control)   MODE="control"; [[ $# -lt 2 ]] && { echo "Error: --control requires a search pattern" >&2; exit 1; }; CONTROL_PATTERN="$2"; shift 2 ;;
    --policy)    MODE="policy"; [[ $# -lt 2 ]] && { echo "Error: --policy requires a search pattern" >&2; exit 1; }; POLICY_PATTERN="$2"; shift 2 ;;
    --gaps)      MODE="gaps"; shift ;;
    --stale)     MODE="stale"; if [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]]; then STALE_DAYS="$2"; shift 2; else shift; fi ;;
    --active)    MODE="active"; shift ;;
    --json)      JSON_OUT=true; shift ;;
    --manifest)  [[ $# -lt 2 ]] && { echo "Error: --manifest requires a file path" >&2; exit 1; }; MANIFEST="$2"; shift 2 ;;
    --help|-h)   head -14 "$0" | tail -13 | sed 's/^# \?//'; exit 0 ;;
    *)           echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
done

# Generate or load manifest
if [[ -n "$MANIFEST" ]]; then
  if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: manifest file not found: $MANIFEST" >&2
    exit 1
  fi
  MANIFEST_DATA=$(cat "$MANIFEST")
else
  MANIFEST_DATA=$(python3 "$SCANNER" 2>/dev/null)
fi

# ============================================================
# Report mode (default) — delegates to provenance-verify.sh
# ============================================================
if [[ "$MODE" == "report" ]]; then
  if $JSON_OUT; then
    bash "$VERIFIER" --json
  else
    bash "$VERIFIER"
  fi
  exit 0
fi

# ============================================================
# Trace mode — end-to-end provenance for a single way
# ============================================================
if [[ "$MODE" == "trace" ]]; then
  WAY_DATA=$(echo "$MANIFEST_DATA" | jq -e --arg w "$TRACE_WAY" '.ways[$w] // empty' 2>/dev/null)

  if [[ -z "$WAY_DATA" ]]; then
    echo "Error: way '$TRACE_WAY' not found in manifest" >&2
    echo "" >&2
    echo "Available ways:" >&2
    echo "$MANIFEST_DATA" | jq -r '.ways | keys[]' >&2
    exit 1
  fi

  HAS_PROV=$(echo "$WAY_DATA" | jq -r '.provenance // empty')

  if $JSON_OUT; then
    echo "$WAY_DATA" | jq --arg w "$TRACE_WAY" '{way: $w} + .'
    exit 0
  fi

  echo "Provenance Trace: $TRACE_WAY"
  echo "$(printf '=%.0s' $(seq 1 $((20 + ${#TRACE_WAY}))))"
  echo ""
  echo "File: $(echo "$WAY_DATA" | jq -r '.path')"
  echo ""

  if [[ -z "$HAS_PROV" ]]; then
    echo "  (no provenance metadata)"
    exit 0
  fi

  echo "Policy sources:"
  echo "$WAY_DATA" | jq -r '.provenance.policy[]? | "  \(.type): \(.uri)"'
  echo ""

  echo "Controls:"
  echo "$WAY_DATA" | jq -r '.provenance.controls[]? | "  \(.)"'
  echo ""

  VERIFIED=$(echo "$WAY_DATA" | jq -r '.provenance.verified // "not set"')
  echo "Verified: $VERIFIED"
  echo ""

  RATIONALE=$(echo "$WAY_DATA" | jq -r '.provenance.rationale // empty')
  if [[ -n "$RATIONALE" ]]; then
    echo "Rationale:"
    echo "  $RATIONALE" | fmt -w 78
  fi

  # If stats exist, show firing data for this way
  if [[ -f "$STATS_FILE" ]]; then
    FIRES=$(jq -r "select(.event == \"way_fired\" and .way == \"$TRACE_WAY\") | .ts" "$STATS_FILE" 2>/dev/null | wc -l)
    if [[ "$FIRES" -gt 0 ]]; then
      FIRST=$(jq -r "select(.event == \"way_fired\" and .way == \"$TRACE_WAY\") | .ts[:10]" "$STATS_FILE" 2>/dev/null | head -1)
      LAST=$(jq -r "select(.event == \"way_fired\" and .way == \"$TRACE_WAY\") | .ts[:10]" "$STATS_FILE" 2>/dev/null | tail -1)
      echo ""
      echo "Firing history: $FIRES times ($FIRST → $LAST)"
    fi
  fi
  exit 0
fi

# ============================================================
# Control mode — which ways implement a control
# ============================================================
if [[ "$MODE" == "control" ]]; then
  MATCHES=$(echo "$MANIFEST_DATA" | jq -r --arg p "$CONTROL_PATTERN" \
    '.coverage.by_control | to_entries[] | select(.key | ascii_downcase | contains($p | ascii_downcase))')

  if [[ -z "$MATCHES" ]]; then
    echo "No controls matching '$CONTROL_PATTERN'" >&2
    echo "" >&2
    echo "Available controls:" >&2
    echo "$MANIFEST_DATA" | jq -r '.coverage.by_control | keys[]' >&2
    exit 1
  fi

  if $JSON_OUT; then
    echo "$MANIFEST_DATA" | jq --arg p "$CONTROL_PATTERN" \
      '[.coverage.by_control | to_entries[] | select(.key | ascii_downcase | contains($p | ascii_downcase))]'
    exit 0
  fi

  echo "Controls matching '$CONTROL_PATTERN':"
  echo ""
  echo "$MANIFEST_DATA" | jq -r --arg p "$CONTROL_PATTERN" \
    '.coverage.by_control | to_entries[] | select(.key | ascii_downcase | contains($p | ascii_downcase)) |
     "  \(.key)\n    implementing: \(.value.addressing_ways | join(", "))\n"'
  exit 0
fi

# ============================================================
# Policy mode — which ways derive from a policy
# ============================================================
if [[ "$MODE" == "policy" ]]; then
  MATCHES=$(echo "$MANIFEST_DATA" | jq -r --arg p "$POLICY_PATTERN" \
    '.coverage.by_policy | to_entries[] | select(.key | ascii_downcase | contains($p | ascii_downcase))')

  if [[ -z "$MATCHES" ]]; then
    echo "No policies matching '$POLICY_PATTERN'" >&2
    echo "" >&2
    echo "Available policies:" >&2
    echo "$MANIFEST_DATA" | jq -r '.coverage.by_policy | keys[]' >&2
    exit 1
  fi

  if $JSON_OUT; then
    echo "$MANIFEST_DATA" | jq --arg p "$POLICY_PATTERN" \
      '[.coverage.by_policy | to_entries[] | select(.key | ascii_downcase | contains($p | ascii_downcase))]'
    exit 0
  fi

  echo "Policies matching '$POLICY_PATTERN':"
  echo ""
  echo "$MANIFEST_DATA" | jq -r --arg p "$POLICY_PATTERN" \
    '.coverage.by_policy | to_entries[] | select(.key | ascii_downcase | contains($p | ascii_downcase)) |
     "  \(.key) (\(.value.type))\n    implementing ways: \(.value.implementing_ways | join(", "))\n"'
  exit 0
fi

# ============================================================
# Gaps mode — ways without provenance
# ============================================================
if [[ "$MODE" == "gaps" ]]; then
  if $JSON_OUT; then
    echo "$MANIFEST_DATA" | jq '.coverage.without_provenance'
    exit 0
  fi

  TOTAL=$(echo "$MANIFEST_DATA" | jq '.ways_scanned')
  WITHOUT=$(echo "$MANIFEST_DATA" | jq '.ways_without_provenance')

  echo "Ways Without Provenance ($WITHOUT of $TOTAL)"
  echo "=============================="
  echo ""
  echo "$MANIFEST_DATA" | jq -r '.coverage.without_provenance[]' | while read -r way; do
    printf "  %s\n" "$way"
  done
  exit 0
fi

# ============================================================
# Stale mode — ways with old verified dates
# ============================================================
if [[ "$MODE" == "stale" ]]; then
  CUTOFF=$(date -d "-${STALE_DAYS} days" +%Y-%m-%d 2>/dev/null \
        || date -v-${STALE_DAYS}d +%Y-%m-%d 2>/dev/null \
        || echo "2025-01-01")

  STALE=$(echo "$MANIFEST_DATA" | jq -r --arg cutoff "$CUTOFF" '
    [.ways | to_entries[] |
     select(.value.provenance != null and .value.provenance.verified != null and .value.provenance.verified < $cutoff) |
     {way: .key, verified: .value.provenance.verified}]')

  if $JSON_OUT; then
    echo "$STALE"
    exit 0
  fi

  COUNT=$(echo "$STALE" | jq 'length')
  echo "Stale Provenance (verified > $STALE_DAYS days ago, cutoff: $CUTOFF)"
  echo ""

  if [[ "$COUNT" -eq 0 ]]; then
    echo "  All provenance dates are current."
  else
    echo "$STALE" | jq -r '.[] | "  \(.way)  (verified: \(.verified))"'
  fi
  exit 0
fi

# ============================================================
# Active mode — cross-reference provenance with firing stats
# ============================================================
if [[ "$MODE" == "active" ]]; then
  if [[ ! -f "$STATS_FILE" ]]; then
    echo "No way firing stats found at $STATS_FILE"
    echo "Stats will appear after ways start firing."
    exit 0
  fi

  # Get ways with provenance
  GOVERNED=$(echo "$MANIFEST_DATA" | jq -r '.coverage.with_provenance[]')

  if $JSON_OUT; then
    # Build JSON: for each governed way, count fires
    RESULT="["
    FIRST=true
    while read -r way; do
      [[ -z "$way" ]] && continue
      FIRES=$(jq -r "select(.event == \"way_fired\" and .way == \"$way\") | .way" "$STATS_FILE" 2>/dev/null | wc -l | tr -d ' ')
      CONTROLS=$(echo "$MANIFEST_DATA" | jq -c --arg w "$way" '[.ways[$w].provenance.controls[]?]')
      $FIRST || RESULT+=","
      RESULT+="{\"way\":\"$way\",\"fires\":$FIRES,\"controls\":$CONTROLS}"
      FIRST=false
    done <<< "$GOVERNED"
    RESULT+="]"
    echo "$RESULT" | jq .
    exit 0
  fi

  TOTAL_GOVERNED=$(echo "$MANIFEST_DATA" | jq '.ways_with_provenance')
  TOTAL_WAYS=$(echo "$MANIFEST_DATA" | jq '.ways_scanned')

  echo "Active Governance Report"
  echo "========================"
  echo ""
  echo "Governed ways: $TOTAL_GOVERNED of $TOTAL_WAYS"
  echo ""

  echo "Way                          Fires  Controls"
  echo "---                          -----  --------"

  while read -r way; do
    [[ -z "$way" ]] && continue
    FIRES=$(jq -r "select(.event == \"way_fired\" and .way == \"$way\") | .way" "$STATS_FILE" 2>/dev/null | wc -l | tr -d ' ')
    CTRL_COUNT=$(echo "$MANIFEST_DATA" | jq --arg w "$way" '[.ways[$w].provenance.controls[]?] | length')

    if [[ "$FIRES" -gt 0 ]]; then
      STATUS="active"
    else
      STATUS="dormant"
    fi

    printf "  %-28s %5d  %d controls (%s)\n" "$way" "$FIRES" "$CTRL_COUNT" "$STATUS"
  done <<< "$GOVERNED"

  # Show ungoverned ways that fire frequently
  echo ""
  echo "Ungoverned ways (top by fire count):"
  UNGOVERNED=$(echo "$MANIFEST_DATA" | jq -r '.coverage.without_provenance[]')
  UNGOV_STATS=""

  while read -r way; do
    [[ -z "$way" ]] && continue
    FIRES=$(jq -r "select(.event == \"way_fired\" and .way == \"$way\") | .way" "$STATS_FILE" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$FIRES" -gt 0 ]] && UNGOV_STATS+="$FIRES $way\n"
  done <<< "$UNGOVERNED"

  if [[ -n "$UNGOV_STATS" ]]; then
    echo -e "$UNGOV_STATS" | sort -rn | head -5 | while read -r fires way; do
      [[ -z "$way" ]] && continue
      printf "  %-28s %5d fires (no provenance)\n" "$way" "$fires"
    done
  else
    echo "  (no firing data for ungoverned ways)"
  fi

  exit 0
fi
