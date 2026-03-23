#!/bin/bash
# Embedding engine status — health dashboard for ADR-108/109
#
# Reports: engine in use, binary/model/corpus state, way counts,
# per-project inclusion status, staleness indicators, and manifest state.
#
# Usage: embed-status [--json]

set -euo pipefail

XDG_WAY="${XDG_CACHE_HOME:-$HOME/.cache}/claude-ways/user"
WAYS_DIR="${HOME}/.claude/hooks/ways"
WAYS_JSON="${HOME}/.claude/ways.json"
MANIFEST="${XDG_WAY}/embed-manifest.json"
PROJECTS_DIR="${HOME}/.claude/projects"

# --- Args ---
JSON=false
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  B='' D='' C='' R=''
  if [[ -t 1 ]]; then B='\033[1m' D='\033[2m' C='\033[0;36m' R='\033[0m'; fi
  echo -e "${B}embed-status${R} — Embedding engine health dashboard"
  echo ""
  echo -e "  ${C}Usage:${R}  embed-status [--json]"
  echo ""
  echo -e "  ${D}Reports engine, binary, model, corpus, manifest state,${R}"
  echo -e "  ${D}per-project inclusion/staleness, and way counts.${R}"
  exit 0
fi
[[ "${1:-}" == "--json" ]] && JSON=true

# --- Colors (disabled for JSON or non-terminal) ---
if [[ -t 1 ]] && ! $JSON; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  DIM='\033[2m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN='' YELLOW='' RED='' CYAN='' DIM='' BOLD='' RESET=''
fi

# --- Binary ---
WAY_EMBED=""
if [[ -x "${XDG_WAY}/way-embed" ]]; then
  WAY_EMBED="${XDG_WAY}/way-embed"
elif [[ -x "${HOME}/.claude/bin/way-embed" ]]; then
  WAY_EMBED="${HOME}/.claude/bin/way-embed"
fi

EMBED_VERSION=""
if [[ -n "$WAY_EMBED" ]]; then
  EMBED_VERSION=$("$WAY_EMBED" --version 2>/dev/null || echo "unknown")
fi

# --- Model ---
MODEL="${XDG_WAY}/minilm-l6-v2.gguf"
MODEL_EXISTS=false
MODEL_SIZE=""
if [[ -f "$MODEL" ]]; then
  MODEL_EXISTS=true
  MODEL_SIZE=$(du -h "$MODEL" 2>/dev/null | cut -f1 || ls -lh "$MODEL" | awk '{print $5}')
fi

# --- Corpus ---
CORPUS="${XDG_WAY}/ways-corpus.jsonl"
CORPUS_EXISTS=false
CORPUS_WAYS=0
CORPUS_EMBEDDED=0
CORPUS_SIZE=""
if [[ -f "$CORPUS" ]]; then
  CORPUS_EXISTS=true
  CORPUS_WAYS=$(wc -l < "$CORPUS")
  CORPUS_EMBEDDED=$(grep -c '"embedding"' "$CORPUS" 2>/dev/null || echo 0)
  CORPUS_SIZE=$(du -h "$CORPUS" 2>/dev/null | cut -f1 || ls -lh "$CORPUS" | awk '{print $5}')
fi

# --- Active engine ---
CONFIGURED=""
if [[ -f "$WAYS_JSON" ]]; then
  CONFIGURED=$(grep -o '"semantic_engine"[[:space:]]*:[[:space:]]*"[^"]*"' "$WAYS_JSON" 2>/dev/null | cut -d'"' -f4 || true)
fi

ENGINE="${CONFIGURED:-auto}"
if [[ "$ENGINE" == "auto" ]]; then
  if [[ -n "$WAY_EMBED" && "$MODEL_EXISTS" == "true" && "$CORPUS_EXISTS" == "true" ]]; then
    ENGINE="embedding (auto)"
  elif [[ -x "${HOME}/.claude/bin/way-match" ]]; then
    ENGINE="bm25 (auto)"
  else
    ENGINE="ncd (auto)"
  fi
fi

# --- Global ways ---
GLOBAL_WAY_COUNT=$(find "$WAYS_DIR" -name "way.md" -type f 2>/dev/null | wc -l)
SEMANTIC_WAY_COUNT=0
while IFS= read -r wf; do
  fm=$(awk 'NR==1 && /^---$/{p=1;next} p && /^---$/{exit} p{print}' "$wf")
  echo "$fm" | grep -q '^description:' && echo "$fm" | grep -q '^vocabulary:' && SEMANTIC_WAY_COUNT=$((SEMANTIC_WAY_COUNT + 1))
done < <(find "$WAYS_DIR" -name "way.md" -type f 2>/dev/null)

# --- Shared library ---
EMBED_LIB="${HOME}/.claude/hooks/ways/embed-lib.sh"
# shellcheck source=embed-lib.sh
source "$EMBED_LIB"

GLOBAL_HASH=$(content_hash "$WAYS_DIR")

# Check global staleness against manifest
GLOBAL_STALE=false
MANIFEST_EXISTS=false
MANIFEST_GLOBAL_HASH=""
if [[ -f "$MANIFEST" ]] && command -v jq &>/dev/null; then
  MANIFEST_EXISTS=true
  MANIFEST_GLOBAL_HASH=$(jq -r '.global_hash // empty' "$MANIFEST" 2>/dev/null)
  [[ "$MANIFEST_GLOBAL_HASH" != "$GLOBAL_HASH" ]] && GLOBAL_STALE=true
fi

# --- Project-local ways (enumerate_projects from embed-lib.sh) ---
# Augments with marker state, staleness, and embedded count per project.

PROJECT_COUNT=0
PROJECT_WAYS=0
PROJECT_EMBEDDED=0
PROJECT_LIST=""

while IFS='|' read -r encoded project_path way_count sem_count; do
    ways_dir="${project_path}/.claude/ways"

    # Check marker state
    marker="${project_path}/.claude/.ways-embed"
    if [[ -f "$marker" ]]; then
      state=$(cat "$marker" 2>/dev/null | tr -d '[:space:]')
    else
      state="no-marker"
    fi

    # Check staleness from manifest
    stale="unknown"
    if $MANIFEST_EXISTS; then
      manifest_hash=$(jq -r --arg k "$encoded" '.projects[$k].ways_hash // empty' "$MANIFEST" 2>/dev/null)
      if [[ -z "$manifest_hash" ]]; then
        stale="not-in-manifest"
      else
        current_hash=$(content_hash "$ways_dir")
        if [[ "$manifest_hash" == "$current_hash" ]]; then
          stale="fresh"
        else
          stale="stale"
        fi
      fi
    fi

    # Count embedded ways in corpus for this project
    embedded=0
    if $CORPUS_EXISTS; then
      embedded=$(grep -c "\"${encoded}/" "$CORPUS" 2>/dev/null || true)
      embedded=${embedded:-0}
    fi

    PROJECT_COUNT=$((PROJECT_COUNT + 1))
    PROJECT_WAYS=$((PROJECT_WAYS + way_count))
    PROJECT_EMBEDDED=$((PROJECT_EMBEDDED + embedded))
    PROJECT_LIST="${PROJECT_LIST}${project_path}|${way_count}|${sem_count}|${state}|${stale}|${embedded}
"

done < <(enumerate_projects || true)

# --- JSON output ---
if $JSON; then
  PROJ_ARRAY=$(echo "$PROJECT_LIST" | awk -F'|' '
    BEGIN { printf "["; n=0 }
    NF >= 6 && $1 != "" {
      if (n > 0) printf ","
      printf "{\"path\":\"%s\",\"ways\":%d,\"semantic\":%d,\"marker\":\"%s\",\"staleness\":\"%s\",\"embedded\":%d}", $1, $2+0, $3+0, $4, $5, $6+0
      n++
    }
    END { printf "]" }
  ')

  cat <<ENDJSON
{
  "engine": "$(echo "$ENGINE" | sed 's/"/\\"/g')",
  "binary": {
    "path": "$WAY_EMBED",
    "version": "$EMBED_VERSION",
    "installed": $([ -n "$WAY_EMBED" ] && echo true || echo false)
  },
  "model": {
    "path": "$MODEL",
    "installed": $MODEL_EXISTS,
    "size": "$MODEL_SIZE"
  },
  "corpus": {
    "path": "$CORPUS",
    "exists": $CORPUS_EXISTS,
    "ways": $CORPUS_WAYS,
    "embedded": $CORPUS_EMBEDDED,
    "size": "$CORPUS_SIZE"
  },
  "manifest": {
    "path": "$MANIFEST",
    "exists": $MANIFEST_EXISTS
  },
  "global_ways": $GLOBAL_WAY_COUNT,
  "semantic_ways": $SEMANTIC_WAY_COUNT,
  "global_hash": "$GLOBAL_HASH",
  "global_stale": $GLOBAL_STALE,
  "projects": {
    "count": $PROJECT_COUNT,
    "ways": $PROJECT_WAYS,
    "embedded": $PROJECT_EMBEDDED,
    "details": $PROJ_ARRAY
  }
}
ENDJSON
  exit 0
fi

# --- Human output ---
echo ""
echo -e "${BOLD}Embedding Engine Status${RESET}"
echo ""

# Engine
echo -e "  Engine:  ${CYAN}${ENGINE}${RESET}"

# Binary
if [[ -n "$WAY_EMBED" ]]; then
  echo -e "  Binary:  ${GREEN}${WAY_EMBED}${RESET} ${DIM}(${EMBED_VERSION})${RESET}"
else
  echo -e "  Binary:  ${RED}not installed${RESET}  ${DIM}(run: make setup)${RESET}"
fi

# Model
if $MODEL_EXISTS; then
  echo -e "  Model:   ${GREEN}${MODEL}${RESET} ${DIM}(${MODEL_SIZE})${RESET}"
else
  echo -e "  Model:   ${RED}not installed${RESET}  ${DIM}(run: make setup)${RESET}"
fi

# Corpus
echo ""
if $CORPUS_EXISTS; then
  echo -e "  Corpus:  ${GREEN}${CORPUS}${RESET} ${DIM}(${CORPUS_SIZE})${RESET}"
  echo -e "  Ways:    ${CORPUS_WAYS} total, ${CORPUS_EMBEDDED} with embeddings"

  if [[ $CORPUS_WAYS -ne $CORPUS_EMBEDDED ]] && [[ $CORPUS_EMBEDDED -gt 0 ]]; then
    echo -e "           ${YELLOW}$((CORPUS_WAYS - CORPUS_EMBEDDED)) ways missing embeddings${RESET}"
  fi
else
  echo -e "  Corpus:  ${RED}not generated${RESET}  ${DIM}(run: make setup)${RESET}"
fi

# Manifest
echo ""
if $MANIFEST_EXISTS; then
  echo -e "  Manifest:  ${GREEN}${MANIFEST}${RESET}"
else
  echo -e "  Manifest:  ${YELLOW}not found${RESET}  ${DIM}(run: make corpus)${RESET}"
fi

# Global ways
echo ""
echo -e "  ${BOLD}Global ways:${RESET}  ${GLOBAL_WAY_COUNT} total, ${SEMANTIC_WAY_COUNT} semantic"
if $GLOBAL_STALE; then
  echo -e "  ${YELLOW}Global ways are stale — corpus needs regen${RESET}"
  echo -e "  ${DIM}Run: make corpus${RESET}"
elif $CORPUS_EXISTS && [[ $SEMANTIC_WAY_COUNT -gt $CORPUS_WAYS ]]; then
  echo -e "  ${YELLOW}Corpus has ${CORPUS_WAYS} entries but ${SEMANTIC_WAY_COUNT}+ semantic ways exist — regen needed${RESET}"
  echo -e "  ${DIM}Run: make corpus${RESET}"
fi

# Project-local ways
if [[ $PROJECT_COUNT -gt 0 ]]; then
  echo ""
  echo -e "  ${BOLD}Project ways:${RESET}  ${PROJECT_WAYS} ways across ${PROJECT_COUNT} projects (${PROJECT_EMBEDDED} embedded)"
  echo "$PROJECT_LIST" | while IFS='|' read -r path wcount scount state stale embedded; do
    [[ -z "$path" ]] && continue
    display_path=$(echo "$path" | sed "s|^$HOME|~|")

    # Status indicator
    case "$state" in
      include)      state_icon="${GREEN}included${RESET}" ;;
      disinclude)   state_icon="${YELLOW}disincluded${RESET}" ;;
      no-marker)    state_icon="${DIM}no marker${RESET}" ;;
      *)            state_icon="${DIM}${state}${RESET}" ;;
    esac

    # Staleness indicator
    case "$stale" in
      fresh)            stale_icon="${GREEN}fresh${RESET}" ;;
      stale)            stale_icon="${YELLOW}stale${RESET}" ;;
      not-in-manifest)  stale_icon="${YELLOW}not embedded${RESET}" ;;
      *)                stale_icon="${DIM}${stale}${RESET}" ;;
    esac

    echo -e "    ${display_path}  ${wcount} ways (${scount} semantic)  ${state_icon}  ${stale_icon}"
  done
fi

# Hash
if [[ -n "$GLOBAL_HASH" ]]; then
  echo ""
  echo -e "  ${DIM}Content hash: ${GLOBAL_HASH:0:16}...${RESET}"
fi

echo ""
