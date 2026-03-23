#!/bin/bash
# Ways of Working - Usage Statistics
# Reads ~/.claude/stats/events.jsonl and Claude project metadata
#
# Usage: stats.sh [--days N] [--project PATH] [--projects] [--json]
#
# Modes:
#   (default)    Aggregated way firing stats
#   --projects   Per-project dashboard (sessions, memory, way fires)
#   --json       Machine-readable output

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  B='' D='' C='' R=''
  if [[ -t 1 ]]; then B='\033[1m' D='\033[2m' C='\033[0;36m' R='\033[0m'; fi
  echo -e "${B}ways-stats${R} — Way firing statistics and project dashboard"
  echo ""
  echo -e "  ${C}Usage:${R}  ways-stats [--days N] [--project PATH] [--projects] [--json]"
  echo ""
  echo -e "  ${D}--days N       Show last N days (default: all)${R}"
  echo -e "  ${D}--project PATH Filter to specific project${R}"
  echo -e "  ${D}--projects     Per-project dashboard mode${R}"
  echo -e "  ${D}--json         Machine-readable output${R}"
  exit 0
fi

STATS_FILE="${HOME}/.claude/stats/events.jsonl"
PROJECTS_DIR="${HOME}/.claude/projects"

# Colors (disabled for non-terminal or --json)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m' YELLOW='\033[1;33m' RED='\033[0;31m'
  CYAN='\033[0;36m' DIM='\033[2m' BOLD='\033[1m' RESET='\033[0m'
else
  GREEN='' YELLOW='' RED='' CYAN='' DIM='' BOLD='' RESET=''
fi

# Normalize a filesystem path to Claude project directory name
# /home/aaron/.claude → -home-aaron--claude
normalize_path() {
  echo "$1" | sed 's|[/.]|-|g'
}

# Reverse: project dir name → display path (best effort, lossy)
# Uses sessions-index.json projectPath if available, falls back to shortened dir name
display_name() {
  local dir_name="$1"
  local idx="${PROJECTS_DIR}/${dir_name}/sessions-index.json"
  if [[ -f "$idx" ]]; then
    local pp=$(jq -r '.entries[0].projectPath // empty' "$idx" 2>/dev/null)
    if [[ -n "$pp" ]]; then
      echo "${pp/#$HOME/~}"
      return
    fi
  fi
  # Fallback: strip leading dash, replace - with /
  echo "~/${dir_name#-home-*-}"
}

# Parse args
DAYS=""
PROJECT_FILTER=""
JSON_OUT=false
PROJECTS_MODE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)     DAYS="$2"; shift 2 ;;
    --project)  PROJECT_FILTER="$2"; shift 2 ;;
    --projects) PROJECTS_MODE=true; shift ;;
    --json)     JSON_OUT=true; shift ;;
    *)          shift ;;
  esac
done

# ============================================================
# Projects mode: per-project dashboard from Claude's project dirs
# ============================================================
if $PROJECTS_MODE; then
  echo ""
  echo -e "${BOLD}Claude Projects Overview${RESET}"
  echo ""

  # Collect events if available
  EVENTS=""
  [[ -f "$STATS_FILE" ]] && EVENTS=$(cat "$STATS_FILE")

  # Apply time filter
  if [[ -n "$DAYS" && -n "$EVENTS" ]]; then
    CUTOFF=$(date -u -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
          || date -u -v-${DAYS}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
    EVENTS=$(echo "$EVENTS" | jq -c "select(.ts >= \"$CUTOFF\")")
  fi

  # Iterate over project directories, sorted by most recently modified
  for dir in $(ls -dt "${PROJECTS_DIR}"/*/); do
    dir_name=$(basename "$dir")
    [[ "$dir_name" == "." || "$dir_name" == ".." ]] && continue

    # Get display name from sessions-index
    name=$(display_name "$dir_name")

    # Session count and last active
    idx="${dir}sessions-index.json"
    sessions="-"
    last_active="-"
    if [[ -f "$idx" ]]; then
      sessions=$(jq '.entries | length' "$idx" 2>/dev/null || echo "-")
      last_active=$(jq -r '[.entries[].modified] | sort | last[:10] // "-"' "$idx" 2>/dev/null || echo "-")
    fi

    # Memory status
    mem_file="${dir}memory/MEMORY.md"
    memory="-"
    if [[ -f "$mem_file" ]] && [[ -s "$mem_file" ]]; then
      memory="$(wc -l < "$mem_file")L"
    elif [[ -f "$mem_file" ]]; then
      memory="empty"
    fi

    # Way fires for this project (match by original project path from events)
    fires=0
    top_ways=""
    if [[ -n "$EVENTS" ]]; then
      # Get the original project path from sessions-index
      orig_path=$(jq -r '.entries[0].projectPath // empty' "$idx" 2>/dev/null)
      if [[ -n "$orig_path" ]]; then
        fires=$(echo "$EVENTS" | jq -r "select(.event == \"way_fired\" and .project == \"$orig_path\") | .way" | wc -l)
        if [[ $fires -gt 0 ]]; then
          top_ways=$(echo "$EVENTS" | jq -r "select(.event == \"way_fired\" and .project == \"$orig_path\") | .way" \
            | sort | uniq -c | sort -rn | head -3 | awk '{printf "%s(%d) ", $2, $1}')
        fi
      fi
    fi

    # Skip inactive projects with no sessions unless showing all
    [[ "$sessions" == "-" || "$sessions" == "0" ]] && [[ $fires -eq 0 ]] && continue

    # Output
    printf "  %-45s" "$name"
    printf "  %3s sessions" "$sessions"
    printf "  │ memory: %-6s" "$memory"
    printf "  │ %3d fires" "$fires"
    echo ""
    if [[ -n "$top_ways" ]]; then
      printf "  %-45s  top: %s\n" "" "$top_ways"
    fi
  done

  echo ""

  # Summary
  total_projects=$(ls -d "${PROJECTS_DIR}"/*/ 2>/dev/null | wc -l)
  with_sessions=0
  for idx in "${PROJECTS_DIR}"/*/sessions-index.json; do
    [[ -f "$idx" ]] && n=$(jq '.entries | length' "$idx" 2>/dev/null) && [[ "$n" -gt 0 ]] && ((with_sessions++))
  done
  with_memory=$(find "${PROJECTS_DIR}" -path "*/memory/MEMORY.md" -size +0c 2>/dev/null | wc -l)

  echo -e "${DIM}Total: ${total_projects} projects, ${with_sessions} with sessions, ${with_memory} with memory${RESET}"
  exit 0
fi

# ============================================================
# Default mode: aggregated way firing stats
# ============================================================

if [[ ! -f "$STATS_FILE" ]]; then
  echo "No events recorded yet. Stats will appear after ways start firing."
  echo "Run with --projects to see Claude project overview."
  exit 0
fi

# Load and filter events
if [[ -n "$DAYS" ]]; then
  CUTOFF=$(date -u -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -v-${DAYS}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  EVENTS=$(jq -c "select(.ts >= \"$CUTOFF\")" "$STATS_FILE")
else
  EVENTS=$(cat "$STATS_FILE")
fi

if [[ -n "$PROJECT_FILTER" ]]; then
  EVENTS=$(echo "$EVENTS" | jq -c "select(.project | contains(\"$PROJECT_FILTER\"))")
fi

# JSON output mode
if $JSON_OUT; then
  echo "$EVENTS" | jq -sc '{
    total_events: length,
    sessions: [.[] | select(.event == "session_start")] | length,
    way_fires: [.[] | select(.event == "way_fired")] | length,
    by_way: ([.[] | select(.event == "way_fired") | .way] | group_by(.) | map({(.[0]): length}) | add // {}),
    by_trigger: ([.[] | select(.event == "way_fired") | .trigger] | group_by(.) | map({(.[0]): length}) | add // {}),
    by_scope: ([.[] | select(.event == "way_fired") | .scope // "unknown"] | group_by(.) | map({(.[0]): length}) | add // {}),
    by_team: ([.[] | select(.event == "way_fired" and .team != null and .team != "") | .team] | group_by(.) | map({(.[0]): length}) | add // {}),
    by_project: ([.[] | select(.event != null) | .project] | group_by(.) | map({(.[0]): length}) | add // {}),
    check_fires: ([.[] | select(.event == "check_fired")] | length),
    by_check: ([.[] | select(.event == "check_fired") | .check] | group_by(.) | map({(.[0]): length}) | add // {}),
    check_avg_distance: ([.[] | select(.event == "check_fired") | .distance | tonumber] | if length > 0 then (add / length) else 0 end),
    check_anchored: ([.[] | select(.event == "check_fired" and .anchored == "true")] | length),
    redisclosures: ([.[] | select(.event == "way_redisclosed")] | length),
    by_redisclosed_way: ([.[] | select(.event == "way_redisclosed") | .way] | group_by(.) | map({(.[0]): length}) | add // {}),
    redisclose_avg_token_distance: ([.[] | select(.event == "way_redisclosed") | .token_distance | tonumber] | if length > 0 then (add / length) else 0 end)
  }'
  exit 0
fi

# --- Human-readable output ---

TOTAL=$(echo "$EVENTS" | wc -l)
SESSIONS=$(echo "$EVENTS" | jq -r 'select(.event == "session_start") | .session' | sort -u | wc -l)
FIRES=$(echo "$EVENTS" | jq -r 'select(.event == "way_fired") | .way' | wc -l)
REDISCLOSURES=$(echo "$EVENTS" | jq -r 'select(.event == "way_redisclosed") | .way' | wc -l)

# Date range
FIRST=$(echo "$EVENTS" | head -1 | jq -r '.ts[:10]')
LAST=$(echo "$EVENTS" | tail -1 | jq -r '.ts[:10]')

echo ""
echo -e "${BOLD}Ways of Working — Usage Stats${RESET}"
echo ""
if [[ -n "$DAYS" ]]; then
  echo -e "  Period:  ${DIM}last ${DAYS} days${RESET}"
elif [[ "$FIRST" != "$LAST" ]]; then
  echo -e "  Period:  ${DIM}${FIRST} → ${LAST}${RESET}"
else
  echo -e "  Date:    ${DIM}${FIRST}${RESET}"
fi
if [[ -n "$PROJECT_FILTER" ]]; then
  echo -e "  Project: ${CYAN}${PROJECT_FILTER}${RESET}"
fi
echo ""
if [[ $REDISCLOSURES -gt 0 ]]; then
  echo -e "  Sessions: ${GREEN}${SESSIONS}${RESET}  |  Way fires: ${GREEN}${FIRES}${RESET}  |  Re-disclosures: ${YELLOW}${REDISCLOSURES}${RESET}"
else
  echo -e "  Sessions: ${GREEN}${SESSIONS}${RESET}  |  Way fires: ${GREEN}${FIRES}${RESET}"
fi
echo ""

# Top ways
echo -e "${BOLD}Top ways:${RESET}"
WAY_COUNTS=$(echo "$EVENTS" | jq -r 'select(.event == "way_fired") | .way' | sort | uniq -c | sort -rn | head -10)
if [[ -z "$WAY_COUNTS" ]]; then
  echo "  (none yet)"
else
  MAX=$(echo "$WAY_COUNTS" | head -1 | awk '{print $1}')
  echo "$WAY_COUNTS" | while read count way; do
    bar_len=$((count * 20 / (MAX > 0 ? MAX : 1)))
    bar=$(printf '█%.0s' $(seq 1 $bar_len 2>/dev/null) || echo "█")
    printf "  %-30s %3d  ${CYAN}%s${RESET}\n" "$way" "$count" "$bar"
  done
fi
echo ""

# By scope (dynamic - shows whatever scopes exist in data)
echo -e "${BOLD}By scope:${RESET}"
echo "$EVENTS" | jq -r 'select(.event == "way_fired") | .scope // "unknown"' | sort | uniq -c | sort -rn | while read count scope; do
  [[ -z "$scope" ]] && continue
  printf "  %-12s %3d\n" "$scope" "$count"
done
echo ""

# By team (if any team events exist)
TEAM_EVENTS=$(echo "$EVENTS" | jq -r 'select(.event == "way_fired" and .team != null and .team != "") | .team')
if [[ -n "$TEAM_EVENTS" ]]; then
  echo -e "${BOLD}By team:${RESET}"
  echo "$TEAM_EVENTS" | sort | uniq -c | sort -rn | while read count team; do
    [[ -z "$team" ]] && continue
    printf "  %-30s %3d fires\n" "$team" "$count"
  done
  echo ""
fi

# By trigger
echo -e "${BOLD}By trigger:${RESET}"
echo "$EVENTS" | jq -r 'select(.event == "way_fired") | .trigger' | sort | uniq -c | sort -rn | while read count trigger; do
  [[ -z "$trigger" ]] && continue
  pct=$((count * 100 / (FIRES > 0 ? FIRES : 1)))
  printf "  %-10s %3d (%d%%)\n" "$trigger" "$count" "$pct"
done
echo ""

# By project (use display names)
echo -e "${BOLD}By project:${RESET}"
echo "$EVENTS" | jq -r 'select(.event == "way_fired") | .project' | sort | uniq -c | sort -rn | head -5 | while read count project; do
  [[ -z "$project" ]] && continue
  display="${project/#$HOME/~}"
  # Try to get project session count
  norm=$(normalize_path "$project")
  idx="${PROJECTS_DIR}/${norm}/sessions-index.json"
  sess=""
  if [[ -f "$idx" ]]; then
    sess=" ($(jq '.entries | length' "$idx" 2>/dev/null) sessions)"
  fi
  printf "  %-40s %3d fires%s\n" "$display" "$count" "$sess"
done
echo ""

# Check stats
CHECK_FIRES=$(echo "$EVENTS" | jq -r 'select(.event == "check_fired") | .check' | wc -l)
if [[ $CHECK_FIRES -gt 0 ]]; then
  echo -e "${BOLD}Check fires:${RESET} ${CHECK_FIRES}"
  echo ""
  echo -e "${BOLD}Top checks:${RESET}"
  echo "$EVENTS" | jq -r 'select(.event == "check_fired") | .check' | sort | uniq -c | sort -rn | head -10 | while read count check; do
    printf "  %-30s %3d\n" "$check" "$count"
  done
  echo ""
  echo "Check distance stats:"
  echo "$EVENTS" | jq -r 'select(.event == "check_fired") | .distance' | awk '
    { sum += $1; count++; if ($1 > max) max = $1; if (count == 1 || $1 < min) min = $1 }
    END { if (count > 0) printf "  avg: %.1f  min: %d  max: %d  total: %d\n", sum/count, min, max, count }
  '
  echo ""
  echo "Anchored vs light:"
  echo "$EVENTS" | jq -r 'select(.event == "check_fired") | .anchored' | sort | uniq -c | sort -rn | while read count anchored; do
    label="light"
    [[ "$anchored" == "true" ]] && label="anchored"
    printf "  %-10s %3d\n" "$label" "$count"
  done
  echo ""
fi

# Re-disclosure stats (ADR-104)
if [[ $REDISCLOSURES -gt 0 ]]; then
  echo -e "${BOLD}Re-disclosures:${RESET} ${YELLOW}${REDISCLOSURES}${RESET}"
  echo ""
  echo -e "${BOLD}Top re-disclosed ways:${RESET}"
  echo "$EVENTS" | jq -r 'select(.event == "way_redisclosed") | .way' | sort | uniq -c | sort -rn | head -10 | while read count way; do
    printf "  %-30s %3d\n" "$way" "$count"
  done
  echo ""
  echo "Token distance at re-disclosure:"
  echo "$EVENTS" | jq -r 'select(.event == "way_redisclosed") | .token_distance' | awk '
    { sum += $1; count++; if ($1 > max) max = $1; if (count == 1 || $1 < min) min = $1 }
    END { if (count > 0) printf "  avg: %.0fk  min: %.0fk  max: %.0fk  total: %d\n", sum/count/1000, min/1000, max/1000, count }
  '
  echo ""
fi

# Recent activity
YESTERDAY=$(date -u -d "1 day ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
         || date -u -v-1d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
if [[ -n "$YESTERDAY" ]]; then
  RECENT_SESSIONS=$(echo "$EVENTS" | jq -r "select(.ts >= \"$YESTERDAY\" and .event == \"session_start\") | .session" | sort -u | wc -l)
  RECENT_FIRES=$(echo "$EVENTS" | jq -r "select(.ts >= \"$YESTERDAY\" and .event == \"way_fired\") | .way" | wc -l)
  echo ""
  echo -e "${DIM}Last 24h: ${RECENT_SESSIONS} sessions, ${RECENT_FIRES} way fires${RESET}"
fi
