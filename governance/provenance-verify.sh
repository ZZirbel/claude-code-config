#!/bin/bash
# Provenance coverage report for ways.
# Reads a provenance manifest and reports traceability coverage.
#
# Usage:
#   provenance-verify.sh [--manifest FILE] [--ledger FILE] [--json]
#
# Options:
#   --manifest FILE   Path to provenance-manifest.json (default: generate on-the-fly)
#   --ledger FILE     Path to external audit ledger JSON (for cross-repo verification)
#   --json            Output as JSON instead of human-readable report
#   --stale-days N    Days before a verified date is considered stale (default: 90)

set -euo pipefail

# Check dependencies
for cmd in jq python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not installed." >&2
    exit 1
  fi
done

# Colors (disabled for non-terminal or --json)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m' YELLOW='\033[1;33m' RED='\033[0;31m'
  CYAN='\033[0;36m' DIM='\033[2m' BOLD='\033[1m' RESET='\033[0m'
else
  GREEN='' YELLOW='' RED='' CYAN='' DIM='' BOLD='' RESET=''
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAYS_DIR="${HOME}/.claude/hooks/ways"
SCANNER="${SCRIPT_DIR}/provenance-scan.py"
MANIFEST=""
LEDGER=""
JSON_OUTPUT=false
STALE_DAYS=90

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) [[ $# -lt 2 ]] && { echo "Error: --manifest requires a file path" >&2; exit 1; }; MANIFEST="$2"; shift 2 ;;
    --ledger) [[ $# -lt 2 ]] && { echo "Error: --ledger requires a file path" >&2; exit 1; }; LEDGER="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    --stale-days) [[ $# -lt 2 ]] && { echo "Error: --stale-days requires a number" >&2; exit 1; }; STALE_DAYS="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Generate manifest if not provided
if [[ -z "$MANIFEST" ]]; then
  MANIFEST_DATA=$(python3 "$SCANNER" 2>/dev/null)
else
  if [[ ! -f "$MANIFEST" ]]; then
    echo "Error: manifest file not found: $MANIFEST" >&2
    exit 1
  fi
  MANIFEST_DATA=$(cat "$MANIFEST")
fi

# Extract stats
TOTAL=$(echo "$MANIFEST_DATA" | jq '.ways_scanned')
WITH=$(echo "$MANIFEST_DATA" | jq '.ways_with_provenance')
WITHOUT=$(echo "$MANIFEST_DATA" | jq '.ways_without_provenance')
POLICIES=$(echo "$MANIFEST_DATA" | jq '.coverage.by_policy | length')
CONTROLS=$(echo "$MANIFEST_DATA" | jq '.coverage.by_control | length')

# Check for stale verified dates
STALE_CUTOFF=$(date -d "-${STALE_DAYS} days" +%Y-%m-%d 2>/dev/null || date -v-${STALE_DAYS}d +%Y-%m-%d 2>/dev/null || echo "2025-01-01")
STALE_WAYS=$(echo "$MANIFEST_DATA" | jq -r --arg cutoff "$STALE_CUTOFF" '
  [.ways | to_entries[] |
   select(.value.provenance != null and .value.provenance.verified != null and .value.provenance.verified < $cutoff) |
   .key] | .[]')

# Check for ways with provenance but missing fields
INCOMPLETE=$(echo "$MANIFEST_DATA" | jq -r '
  [.ways | to_entries[] |
   select(.value.provenance != null) |
   select(.value.provenance.policy == [] or .value.provenance.controls == [] or .value.provenance.rationale == null) |
   .key] | .[]')

if $JSON_OUTPUT; then
  # JSON output
  STALE_JSON=$(echo "$MANIFEST_DATA" | jq --arg cutoff "$STALE_CUTOFF" '
    [.ways | to_entries[] |
     select(.value.provenance != null and .value.provenance.verified != null and .value.provenance.verified < $cutoff) |
     .key]')

  INCOMPLETE_JSON=$(echo "$MANIFEST_DATA" | jq '
    [.ways | to_entries[] |
     select(.value.provenance != null) |
     select(.value.provenance.policy == [] or .value.provenance.controls == [] or .value.provenance.rationale == null) |
     .key]')

  jq -n \
    --argjson total "$TOTAL" \
    --argjson with "$WITH" \
    --argjson without "$WITHOUT" \
    --argjson policies "$POLICIES" \
    --argjson controls "$CONTROLS" \
    --argjson stale "$STALE_JSON" \
    --argjson incomplete "$INCOMPLETE_JSON" \
    --argjson by_control "$(echo "$MANIFEST_DATA" | jq '.coverage.by_control')" \
    --argjson by_policy "$(echo "$MANIFEST_DATA" | jq '.coverage.by_policy')" \
    '{
      total_ways: $total,
      with_provenance: $with,
      without_provenance: $without,
      coverage_pct: (if $total > 0 then ($with / $total * 100) | floor else 0 end),
      policy_sources: $policies,
      control_references: $controls,
      stale_ways: $stale,
      incomplete_ways: $incomplete,
      by_control: $by_control,
      by_policy: $by_policy
    }'
  exit 0
fi

# Human-readable output
echo ""
echo -e "${BOLD}Provenance Coverage Report${RESET}"
echo ""

# Coverage with color-coded percentage
if [[ "$TOTAL" -gt 0 ]]; then
  PCT=$((WITH * 100 / TOTAL))
  if [[ $PCT -ge 75 ]]; then
    PCT_COLOR="$GREEN"
  elif [[ $PCT -ge 40 ]]; then
    PCT_COLOR="$YELLOW"
  else
    PCT_COLOR="$RED"
  fi
  printf "  Ways scanned:        %3d\n" "$TOTAL"
  printf "  With provenance:     ${PCT_COLOR}%3d (%d%%)${RESET}\n" "$WITH" "$PCT"
  printf "  Without provenance:  %3d\n" "$WITHOUT"
else
  printf "  Ways scanned:        %3d\n" "$TOTAL"
  printf "  With provenance:     %3d\n" "$WITH"
  printf "  Without provenance:  %3d\n" "$WITHOUT"
fi
echo ""

echo -e "${BOLD}Policy Sources${RESET} ${DIM}(${POLICIES}):${RESET}"
echo "$MANIFEST_DATA" | jq -r '.coverage.by_policy | to_entries[] | .key' | while read -r policy; do
  WAYS=$(echo "$MANIFEST_DATA" | jq -r --arg p "$policy" '.coverage.by_policy[$p].implementing_ways | join(", ")')
  echo -e "  ${CYAN}${policy}${RESET}"
  echo -e "    ${DIM}→ ${WAYS}${RESET}"
done
echo ""

echo -e "${BOLD}Control References${RESET} ${DIM}(${CONTROLS}):${RESET}"
echo "$MANIFEST_DATA" | jq -r '.coverage.by_control | to_entries[] | .key' | while read -r control; do
  WAYS=$(echo "$MANIFEST_DATA" | jq -r --arg c "$control" '.coverage.by_control[$c].addressing_ways | join(", ")')
  echo -e "  ${control}"
  echo -e "    ${DIM}→ ${WAYS}${RESET}"
done
echo ""

if [[ -n "$STALE_WAYS" ]]; then
  echo -e "${BOLD}Stale Provenance${RESET} ${YELLOW}(verified > ${STALE_DAYS} days ago):${RESET}"
  echo "$STALE_WAYS" | while read -r way; do
    VERIFIED=$(echo "$MANIFEST_DATA" | jq -r --arg w "$way" '.ways[$w].provenance.verified')
    echo -e "  ${YELLOW}${way}${RESET} ${DIM}(verified: ${VERIFIED})${RESET}"
  done
  echo ""
fi

if [[ -n "$INCOMPLETE" ]]; then
  echo -e "${BOLD}Incomplete Provenance${RESET} ${YELLOW}(missing policy, controls, or rationale):${RESET}"
  echo "$INCOMPLETE" | while read -r way; do
    echo -e "  ${YELLOW}${way}${RESET}"
  done
  echo ""
fi

# Cross-reference with external audit ledger if provided
if [[ -n "$LEDGER" && -f "$LEDGER" ]]; then
  echo -e "${BOLD}Cross-Repo Verification${RESET} ${DIM}($(basename "$LEDGER")):${RESET}"

  # Get control IDs from ledger
  LEDGER_CONTROLS=$(jq -r '.control_disposition_map | keys[]' "$LEDGER" 2>/dev/null)
  if [[ -n "$LEDGER_CONTROLS" ]]; then
    LEDGER_COUNT=$(echo "$LEDGER_CONTROLS" | wc -l | tr -d ' ')
    echo "  Controls in ledger: $LEDGER_COUNT"

    # Check which ledger controls have implementing ways
    COVERED=0
    UNCOVERED=""
    while read -r cid; do
      # Check if any way references this control ID (substring match)
      HAS_WAY=$(echo "$MANIFEST_DATA" | jq -r --arg cid "$cid" '
        [.coverage.by_control | to_entries[] | select(.key | contains($cid)) | .key] | length')
      if [[ "$HAS_WAY" -gt 0 ]]; then
        COVERED=$((COVERED + 1))
      else
        UNCOVERED="${UNCOVERED}\n    $cid"
      fi
    done <<< "$LEDGER_CONTROLS"

    echo "  Controls with implementing ways: $COVERED"
    echo "  Controls without implementing ways: $((LEDGER_COUNT - COVERED))"

    if [[ -n "$UNCOVERED" ]]; then
      echo "  Gaps:"
      echo -e "$UNCOVERED"
    fi
  else
    echo "  No control_disposition_map found in ledger"
  fi
  echo ""
fi

echo -e "${BOLD}Ways without provenance:${RESET}"
echo "$MANIFEST_DATA" | jq -r '.coverage.without_provenance[]' | while read -r way; do
  echo -e "  ${DIM}${way}${RESET}"
done
echo ""
