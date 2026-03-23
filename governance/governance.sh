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
#   governance.sh --matrix                Flat spreadsheet: way | control | justification
#   governance.sh --lint                  Validate provenance integrity
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

# Colors (disabled for non-terminal or --json)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m' YELLOW='\033[1;33m' RED='\033[0;31m'
  CYAN='\033[0;36m' DIM='\033[2m' BOLD='\033[1m' RESET='\033[0m'
else
  GREEN='' YELLOW='' RED='' CYAN='' DIM='' BOLD='' RESET=''
fi

# Check dependencies
for cmd in jq python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}Error:${RESET} $cmd is required but not installed." >&2
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
    --matrix)    MODE="matrix"; shift ;;
    --lint)      MODE="lint"; shift ;;
    --json)      JSON_OUT=true; shift ;;
    --manifest)  [[ $# -lt 2 ]] && { echo "Error: --manifest requires a file path" >&2; exit 1; }; MANIFEST="$2"; shift 2 ;;
    --help|-h)
      _B='' _D='' _C='' _R=''
      if [[ -t 1 ]]; then _B='\033[1m' _D='\033[2m' _C='\033[0;36m' _R='\033[0m'; fi
      echo -e "${_B}governance-report${_R} — Provenance traceability for ways"
      echo ""
      echo -e "  ${_C}Usage:${_R}  governance-report [mode] [--json]"
      echo ""
      echo -e "  ${_D}(default)          Coverage report${_R}"
      echo -e "  ${_D}--trace WAY        End-to-end trace for a way${_R}"
      echo -e "  ${_D}--control PATTERN   Which ways implement a control${_R}"
      echo -e "  ${_D}--policy PATTERN    Which ways derive from a policy${_R}"
      echo -e "  ${_D}--gaps             Ways without provenance${_R}"
      echo -e "  ${_D}--stale [DAYS]     Stale verified dates (default: 90)${_R}"
      echo -e "  ${_D}--active           Cross-reference with firing stats${_R}"
      echo -e "  ${_D}--matrix           Flat: way | control | justification${_R}"
      echo -e "  ${_D}--lint             Validate provenance integrity${_R}"
      echo -e "  ${_D}--json             Machine-readable output (any mode)${_R}"
      exit 0
      ;;
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
  WAY_DATA=$(echo "$MANIFEST_DATA" | jq --arg w "$TRACE_WAY" '.ways[$w] // empty' 2>/dev/null)

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

  echo ""
  echo -e "${BOLD}Provenance Trace: ${CYAN}${TRACE_WAY}${RESET}"
  echo ""
  echo -e "  File: ${DIM}$(echo "$WAY_DATA" | jq -r '.path')${RESET}"
  echo ""

  if [[ -z "$HAS_PROV" ]]; then
    echo -e "  ${YELLOW}(no provenance metadata)${RESET}"
    exit 0
  fi

  echo -e "${BOLD}Policy sources:${RESET}"
  echo "$WAY_DATA" | jq -r '.provenance.policy[]? | "  \(.type): \(.uri)"'
  echo ""

  echo -e "${BOLD}Controls:${RESET}"
  echo "$WAY_DATA" | jq -r '.provenance.controls[]? |
    if type == "object" then
      "  \(.id)\n\(.justifications // [] | map("    ✓ \(.)") | join("\n"))"
    else
      "  \(.)"
    end'
  echo ""

  VERIFIED=$(echo "$WAY_DATA" | jq -r '.provenance.verified // "not set"')
  if [[ "$VERIFIED" == "not set" ]]; then
    echo -e "  Verified: ${YELLOW}${VERIFIED}${RESET}"
  else
    echo -e "  Verified: ${GREEN}${VERIFIED}${RESET}"
  fi
  echo ""

  RATIONALE=$(echo "$WAY_DATA" | jq -r '.provenance.rationale // empty')
  if [[ -n "$RATIONALE" ]]; then
    echo -e "${BOLD}Rationale:${RESET}"
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

  echo -e "${BOLD}Controls matching${RESET} '${CYAN}${CONTROL_PATTERN}${RESET}':"
  echo ""
  echo "$MANIFEST_DATA" | jq -r --arg p "$CONTROL_PATTERN" \
    '.coverage.by_control | to_entries[] | select(.key | ascii_downcase | contains($p | ascii_downcase)) |
     "  \(.key)\n    implementing: \(.value.addressing_ways | join(", "))" +
     (if (.value.justifications | length) > 0 then
       "\n" + ([.value.justifications | to_entries[] | .key as $way |
         .value[] | "    ✓ [\($way)] \(.)"] | join("\n"))
     else "" end) + "\n"'
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

  echo -e "${BOLD}Policies matching${RESET} '${CYAN}${POLICY_PATTERN}${RESET}':"
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

  echo ""
  echo -e "${BOLD}Ways Without Provenance${RESET} ${YELLOW}(${WITHOUT} of ${TOTAL})${RESET}"
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
  echo ""
  echo -e "${BOLD}Stale Provenance${RESET} ${DIM}(verified > ${STALE_DAYS} days ago, cutoff: ${CUTOFF})${RESET}"
  echo ""

  if [[ "$COUNT" -eq 0 ]]; then
    echo -e "  ${GREEN}All provenance dates are current.${RESET}"
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
    # Build JSON via jq: for each governed way, count fires
    FIRE_COUNTS="{}"
    while read -r way; do
      [[ -z "$way" ]] && continue
      COUNT=$(jq -r "select(.event == \"way_fired\" and .way == \"$way\") | .way" "$STATS_FILE" 2>/dev/null | wc -l | tr -d ' ')
      FIRE_COUNTS=$(echo "$FIRE_COUNTS" | jq --arg w "$way" --argjson c "$COUNT" '. + {($w): $c}')
    done <<< "$GOVERNED"
    echo "$MANIFEST_DATA" | jq --argjson fires "$FIRE_COUNTS" '[
      .coverage.with_provenance[] as $way |
      {way: $way, fires: ($fires[$way] // 0), controls: .ways[$way].provenance.controls}
    ]'
    exit 0
  fi

  TOTAL_GOVERNED=$(echo "$MANIFEST_DATA" | jq '.ways_with_provenance')
  TOTAL_WAYS=$(echo "$MANIFEST_DATA" | jq '.ways_scanned')

  echo ""
  echo -e "${BOLD}Active Governance Report${RESET}"
  echo ""
  echo -e "  Governed ways: ${GREEN}${TOTAL_GOVERNED}${RESET} of ${TOTAL_WAYS}"
  echo ""

  printf "  ${BOLD}%-28s %5s  %s${RESET}\n" "Way" "Fires" "Controls"
  printf "  ${DIM}%-28s %5s  %s${RESET}\n" "---" "-----" "--------"

  while read -r way; do
    [[ -z "$way" ]] && continue
    FIRES=$(jq -r "select(.event == \"way_fired\" and .way == \"$way\") | .way" "$STATS_FILE" 2>/dev/null | wc -l | tr -d ' ')
    CTRL_COUNT=$(echo "$MANIFEST_DATA" | jq --arg w "$way" '[.ways[$w].provenance.controls[]?] | length')

    if [[ "$FIRES" -gt 0 ]]; then
      STATUS="${GREEN}active${RESET}"
    else
      STATUS="${DIM}dormant${RESET}"
    fi

    printf "  %-28s %5d  %d controls (${STATUS})\n" "$way" "$FIRES" "$CTRL_COUNT"
  done <<< "$GOVERNED"

  # Show ungoverned ways that fire frequently
  echo ""
  echo -e "${BOLD}Ungoverned ways${RESET} ${DIM}(top by fire count):${RESET}"
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
      printf "  %-28s %5d fires ${YELLOW}(no provenance)${RESET}\n" "$way" "$fires"
    done
  else
    echo "  (no firing data for ungoverned ways)"
  fi

  exit 0
fi

# ============================================================
# Matrix mode — flat spreadsheet: way | control | justification
# ============================================================
if [[ "$MODE" == "matrix" ]]; then
  if $JSON_OUT; then
    echo "$MANIFEST_DATA" | jq '[
      .ways | to_entries[] |
      select(.value.provenance != null) |
      .key as $way |
      .value.provenance.controls[] |
      if type == "object" then
        .id as $ctrl |
        if (.justifications | length) > 0 then
          .justifications[] | {way: $way, control: $ctrl, justification: .}
        else
          {way: $way, control: $ctrl, justification: null}
        end
      else
        {way: $way, control: ., justification: null}
      end
    ]'
    exit 0
  fi

  echo ""
  echo -e "${BOLD}Governance Traceability Matrix${RESET}"
  echo ""
  printf "  ${BOLD}%-28s %-50s %s${RESET}\n" "WAY" "CONTROL" "JUSTIFICATION"
  printf "  ${DIM}%-28s %-50s %s${RESET}\n" "---" "-------" "-------------"

  echo "$MANIFEST_DATA" | jq -r '
    .ways | to_entries[] |
    select(.value.provenance != null) |
    .key as $way |
    .value.provenance.controls[] |
    if type == "object" then
      .id as $ctrl |
      if (.justifications | length) > 0 then
        .justifications[] | "\($way)\t\($ctrl)\t\(.)"
      else
        "\($way)\t\($ctrl)\t(no justification)"
      end
    else
      "\($way)\t\(.)\t(legacy — no justification)"
    end' | while IFS=$'\t' read -r way control justification; do
    printf "%-28s %-50s %s\n" "$way" "${control:0:50}" "$justification"
  done

  echo ""
  TOTAL_J=$(echo "$MANIFEST_DATA" | jq '[.ways[].provenance? // empty | .controls[]? | select(type == "object") | .justifications[]?] | length')
  TOTAL_C=$(echo "$MANIFEST_DATA" | jq '[.ways[].provenance? // empty | .controls[]?] | length')
  echo -e "  ${DIM}Total: ${TOTAL_C} control claims, ${TOTAL_J} justifications${RESET}"
  exit 0
fi

# ============================================================
# Lint mode — validate provenance integrity
# ============================================================
if [[ "$MODE" == "lint" ]]; then
  ERRORS=0
  WARNINGS=0

  $JSON_OUT || echo ""
  $JSON_OUT || echo -e "${BOLD}Governance Lint Report${RESET}"
  $JSON_OUT || echo ""

  WAYS_DIR="${HOME}/.claude/hooks/ways"
  LINT_RESULTS=""

  # Check each way with provenance
  while read -r way; do
    PROV=$(echo "$MANIFEST_DATA" | jq --arg w "$way" '.ways[$w].provenance')

    # Check: controls exist
    CTRL_COUNT=$(echo "$PROV" | jq '[.controls[]?] | length')
    if [[ "$CTRL_COUNT" -eq 0 ]]; then
      ((ERRORS++))
      LINT_RESULTS+="ERROR|$way|provenance declared but no controls listed\n"
    fi

    # Check: each structured control has justifications
    while read -r ctrl_id; do
      [[ -z "$ctrl_id" ]] && continue
      J_COUNT=$(echo "$PROV" | jq --arg c "$ctrl_id" '[.controls[] | select(type == "object" and .id == $c) | .justifications[]?] | length')
      if [[ "$J_COUNT" -eq 0 ]]; then
        ((WARNINGS++))
        LINT_RESULTS+="WARN|$way|control has no justifications: ${ctrl_id:0:60}\n"
      fi
    done < <(echo "$PROV" | jq -r '.controls[]? | select(type == "object") | .id')

    # Check: legacy string controls (no justifications possible)
    LEGACY=$(echo "$PROV" | jq '[.controls[]? | select(type == "string")] | length')
    if [[ "$LEGACY" -gt 0 ]]; then
      ((WARNINGS++))
      LINT_RESULTS+="WARN|$way|$LEGACY control(s) in legacy format (no justifications)\n"
    fi

    # Check: policy URIs reference real files
    while read -r uri; do
      [[ -z "$uri" ]] && continue
      if [[ "$uri" != github://* && "$uri" != http* ]]; then
        FULL_PATH="${HOME}/.claude/$uri"
        if [[ ! -f "$FULL_PATH" ]]; then
          ((ERRORS++))
          LINT_RESULTS+="ERROR|$way|policy URI not found: $uri\n"
        fi
      fi
    done < <(echo "$PROV" | jq -r '.policy[]?.uri')

    # Check: verified date is valid format
    VERIFIED=$(echo "$PROV" | jq -r '.verified // empty')
    if [[ -z "$VERIFIED" ]]; then
      ((WARNINGS++))
      LINT_RESULTS+="WARN|$way|no verified date\n"
    elif ! [[ "$VERIFIED" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      ((ERRORS++))
      LINT_RESULTS+="ERROR|$way|invalid verified date: $VERIFIED\n"
    fi

    # Check: rationale exists
    RATIONALE=$(echo "$PROV" | jq -r '.rationale // empty')
    if [[ -z "$RATIONALE" ]]; then
      ((WARNINGS++))
      LINT_RESULTS+="WARN|$way|no rationale\n"
    fi
  done < <(echo "$MANIFEST_DATA" | jq -r '.ways | to_entries[] | select(.value.provenance != null) | .key')

  if $JSON_OUT; then
    if [[ -n "$LINT_RESULTS" ]]; then
      ERROR_LIST=$(echo -e "$LINT_RESULTS" | grep "^ERROR" | awk -F'|' '{print "{\"way\":\""$2"\",\"message\":\""$3"\"}"}' | jq -s '.' 2>/dev/null || echo "[]")
      WARN_LIST=$(echo -e "$LINT_RESULTS" | grep "^WARN" | awk -F'|' '{print "{\"way\":\""$2"\",\"message\":\""$3"\"}"}' | jq -s '.' 2>/dev/null || echo "[]")
    else
      ERROR_LIST="[]"
      WARN_LIST="[]"
    fi
    jq -n --argjson errors "$ERROR_LIST" --argjson warnings "$WARN_LIST" \
      --argjson error_count "$ERRORS" --argjson warning_count "$WARNINGS" \
      '{errors: $error_count, warnings: $warning_count, passed: ($error_count == 0),
        error_details: $errors, warning_details: $warnings}'
    exit $(( ERRORS > 0 ? 1 : 0 ))
  fi

  # Human output
  if [[ -n "$LINT_RESULTS" ]]; then
    echo -e "$LINT_RESULTS" | while IFS='|' read -r level way msg; do
      [[ -z "$level" ]] && continue
      if [[ "$level" == "ERROR" ]]; then
        printf "  ${RED}%-6s${RESET} [%-28s] %s\n" "$level" "$way" "$msg"
      else
        printf "  ${YELLOW}%-6s${RESET} [%-28s] %s\n" "$level" "$way" "$msg"
      fi
    done
    echo ""
  fi

  if [[ "$ERRORS" -eq 0 && "$WARNINGS" -eq 0 ]]; then
    echo -e "  ${GREEN}All provenance checks passed.${RESET}"
  else
    echo -e "  Results: ${RED}${ERRORS} error(s)${RESET}, ${YELLOW}${WARNINGS} warning(s)${RESET}"
    [[ "$ERRORS" -gt 0 ]] && echo -e "  ${RED}Lint FAILED — errors must be resolved.${RESET}"
  fi
  exit $(( ERRORS > 0 ? 1 : 0 ))
fi
