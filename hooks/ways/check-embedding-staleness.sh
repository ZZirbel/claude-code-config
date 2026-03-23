#!/bin/bash
# Embedding corpus staleness check — runs at session start (ADR-109)
#
# Checks global ways + current project only. If either is stale,
# triggers a full corpus regen (which sweeps all valid projects).
#
# Cost: one find+sha256sum for global + one for current project (~10ms).
# Full project crawl happens in generate-corpus.sh, not here.
#
# Output: none on fresh, silent background regen on stale.

set -euo pipefail

XDG_WAY="${XDG_CACHE_HOME:-$HOME/.cache}/claude-ways/user"
MANIFEST="${XDG_WAY}/embed-manifest.json"
CORPUS="${XDG_WAY}/ways-corpus.jsonl"
CORPUS_GEN="${HOME}/.claude/tools/way-match/generate-corpus.sh"
WAYS_DIR="${HOME}/.claude/hooks/ways"
REGEN_LOG="${XDG_WAY}/regen.log"

# Current project from Claude Code environment
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

# Need jq for manifest parsing
command -v jq &>/dev/null || exit 0

# No corpus generator → nothing to do
[[ -x "$CORPUS_GEN" ]] || exit 0

# Shared library: content_hash, resolve_project_path
EMBED_LIB="${HOME}/.claude/hooks/ways/embed-lib.sh"
# shellcheck source=embed-lib.sh
[[ -f "$EMBED_LIB" ]] && source "$EMBED_LIB" || exit 0

# ── Missing manifest or corpus → full regen ──────────────────────
if [[ ! -f "$MANIFEST" || ! -f "$CORPUS" ]]; then
  bash "$CORPUS_GEN" --quiet >> "$REGEN_LOG" 2>&1 &
  exit 0
fi

# ── Check global ways staleness ──────────────────────────────────
STALE=false

manifest_global_hash=$(jq -r '.global_hash // empty' "$MANIFEST" 2>/dev/null)
current_global_hash=$(content_hash "$WAYS_DIR")

if [[ "$manifest_global_hash" != "$current_global_hash" ]]; then
  STALE=true
fi

# ── Check current project ways staleness ─────────────────────────
# Only checks the project we're in, not all projects. The full crawl
# happens in generate-corpus.sh when regen is triggered.
if [[ "$STALE" == "false" && -n "$PROJECT_DIR" && -d "${PROJECT_DIR}/.claude/ways" ]]; then
  # Encode project path the same way Claude Code does
  encoded=$(echo "$PROJECT_DIR" | tr '/' '-')

  # Check marker
  marker="${PROJECT_DIR}/.claude/.ways-embed"
  if [[ ! -f "$marker" ]] || [[ "$(cat "$marker" 2>/dev/null | tr -d '[:space:]')" != "disinclude" ]]; then
    manifest_hash=$(jq -r --arg k "$encoded" '.projects[$k].ways_hash // empty' "$MANIFEST" 2>/dev/null)

    if [[ -z "$manifest_hash" ]]; then
      # Project with ways not yet in manifest → stale
      STALE=true
    else
      current_hash=$(content_hash "${PROJECT_DIR}/.claude/ways")
      if [[ "$manifest_hash" != "$current_hash" ]]; then
        STALE=true
      fi
    fi
  fi
fi

# ── Trigger regen if stale ───────────────────────────────────────
# Full regen sweeps all valid projects, not just the current one.
# Logs to regen.log so persistent failures don't silently retry.
if [[ "$STALE" == "true" ]]; then
  echo "[$(date -Iseconds)] staleness detected, triggering regen" >> "$REGEN_LOG"
  bash "$CORPUS_GEN" --quiet >> "$REGEN_LOG" 2>&1 &
fi
