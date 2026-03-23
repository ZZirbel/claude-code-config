#!/bin/bash
# Embedding engine status — health dashboard for ADR-108/109
#
# Reports: engine in use, binary/model/corpus state, way counts,
# per-project inclusion status, and staleness indicators.
#
# Usage: embed-status [--json]

set -euo pipefail

XDG_WAY="${XDG_CACHE_HOME:-$HOME/.cache}/claude-ways/user"
WAYS_DIR="${HOME}/.claude/hooks/ways"
WAYS_JSON="${HOME}/.claude/ways.json"

# --- Output mode ---
JSON=false
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
  MODEL_SIZE=$(ls -lh "$MODEL" 2>/dev/null | awk '{print $5}')
fi

# --- Corpus ---
CORPUS="${XDG_WAY}/ways-corpus.jsonl"
CORPUS_EXISTS=false
CORPUS_WAYS=0
CORPUS_EMBEDDED=0
CORPUS_SIZE=""
CORPUS_MTIME=""
if [[ -f "$CORPUS" ]]; then
  CORPUS_EXISTS=true
  CORPUS_WAYS=$(wc -l < "$CORPUS")
  CORPUS_EMBEDDED=$(grep -c '"embedding"' "$CORPUS" 2>/dev/null || echo 0)
  CORPUS_SIZE=$(ls -lh "$CORPUS" 2>/dev/null | awk '{print $5}')
  CORPUS_MTIME=$(stat -c '%Y' "$CORPUS" 2>/dev/null || stat -f '%m' "$CORPUS" 2>/dev/null || echo 0)
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
# Count semantic ways (have both description and vocabulary in frontmatter)
SEMANTIC_WAY_COUNT=0
while IFS= read -r wf; do
  fm=$(awk 'NR==1 && /^---$/{p=1;next} p && /^---$/{exit} p{print}' "$wf")
  echo "$fm" | grep -q '^description:' && echo "$fm" | grep -q '^vocabulary:' && SEMANTIC_WAY_COUNT=$((SEMANTIC_WAY_COUNT + 1))
done < <(find "$WAYS_DIR" -name "way.md" -type f 2>/dev/null)

# --- Content hash (for staleness) ---
GLOBAL_HASH=""
if command -v sha256sum &>/dev/null; then
  GLOBAL_HASH=$(find "$WAYS_DIR" -name "way.md" -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum | cut -d' ' -f1)
elif command -v shasum &>/dev/null; then
  GLOBAL_HASH=$(find "$WAYS_DIR" -name "way.md" -type f -exec shasum -a 256 {} + 2>/dev/null | sort | shasum -a 256 | cut -d' ' -f1)
fi

# --- Project-local ways ---
PROJECTS_DIR="${HOME}/.claude/projects"
PROJECT_COUNT=0
PROJECT_WAYS=0
PROJECT_LIST=""

if [[ -d "$PROJECTS_DIR" ]]; then
  while IFS= read -r projdir; do
    encoded=$(basename "$projdir")
    # Decode: replace leading - with /, then remaining - with /
    decoded=$(echo "$encoded" | sed 's/^-/\//; s/-/\//g')

    if [[ -d "${decoded}/.claude/ways" ]]; then
      count=$(find "${decoded}/.claude/ways" -name "way.md" -type f 2>/dev/null | wc -l)
      if [[ $count -gt 0 ]]; then
        PROJECT_COUNT=$((PROJECT_COUNT + 1))
        PROJECT_WAYS=$((PROJECT_WAYS + count))
        PROJECT_LIST="${PROJECT_LIST}${decoded}:${count}
"
      fi
    fi
  done < <(find "$PROJECTS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
fi

# --- JSON output ---
if $JSON; then
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
  "global_ways": $GLOBAL_WAY_COUNT,
  "global_hash": "$GLOBAL_HASH",
  "projects": {
    "count": $PROJECT_COUNT,
    "ways": $PROJECT_WAYS
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

# Global ways
echo ""
echo -e "  ${BOLD}Global ways:${RESET}  ${GLOBAL_WAY_COUNT} total, ${SEMANTIC_WAY_COUNT} semantic"
if $CORPUS_EXISTS && [[ $SEMANTIC_WAY_COUNT -ne $CORPUS_WAYS ]]; then
  echo -e "  ${YELLOW}Corpus has ${CORPUS_WAYS} entries but ${SEMANTIC_WAY_COUNT} semantic ways exist — regen needed${RESET}"
  echo -e "  ${DIM}Run: make corpus${RESET}"
fi

# Project-local ways
if [[ $PROJECT_COUNT -gt 0 ]]; then
  echo ""
  echo -e "  ${BOLD}Project ways:${RESET}  ${PROJECT_WAYS} ways across ${PROJECT_COUNT} projects"
  echo "$PROJECT_LIST" | while IFS=: read -r path count; do
    [[ -z "$path" ]] && continue
    echo -e "    ${DIM}${path}${RESET}  ${count} ways"
  done
  echo -e "  ${DIM}(project ways not yet embedded — see ADR-109)${RESET}"
fi

# Hash
if [[ -n "$GLOBAL_HASH" ]]; then
  echo ""
  echo -e "  ${DIM}Content hash: ${GLOBAL_HASH:0:16}...${RESET}"
fi

echo ""
