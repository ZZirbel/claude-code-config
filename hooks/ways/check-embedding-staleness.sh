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
WAYS_BIN="${HOME}/.claude/bin/ways"
WAYS_DIR="${HOME}/.claude/hooks/ways"
REGEN_LOG="${XDG_WAY}/regen.log"

# Current project from Claude Code environment
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

# Need jq for manifest parsing
command -v jq &>/dev/null || exit 0

# No ways binary → nothing to do
[[ -x "$WAYS_BIN" ]] || exit 0

# ── Missing manifest or corpus → full regen ──────────────────────
if [[ ! -f "$MANIFEST" || ! -f "$CORPUS" ]]; then
  "$WAYS_BIN" corpus --quiet >> "$REGEN_LOG" 2>&1 &
  exit 0
fi

# ── Check global ways staleness ──────────────────────────────────
STALE=false

manifest_global_hash=$(jq -r '.global_hash // empty' "$MANIFEST" 2>/dev/null)
# Quick staleness heuristic: compare manifest timestamp vs newest way file
manifest_mtime=$(stat -c %Y "$MANIFEST" 2>/dev/null || stat -f %m "$MANIFEST" 2>/dev/null || echo 0)
newest_way=$(find -L "$WAYS_DIR" -name "*.md" -newer "$MANIFEST" -print -quit 2>/dev/null)

if [[ -n "$newest_way" ]]; then
  STALE=true
fi

# ── Check current project ways staleness ─────────────────────────
if [[ "$STALE" == "false" && -n "$PROJECT_DIR" && -d "${PROJECT_DIR}/.claude/ways" ]]; then
  newest_project_way=$(find -L "${PROJECT_DIR}/.claude/ways" -name "*.md" -newer "$MANIFEST" -print -quit 2>/dev/null)
  if [[ -n "$newest_project_way" ]]; then
    STALE=true
  fi
fi

# ── Trigger regen if stale ───────────────────────────────────────
if [[ "$STALE" == "true" ]]; then
  echo "[$(date -Iseconds)] staleness detected, triggering regen" >> "$REGEN_LOG"
  "$WAYS_BIN" corpus --quiet >> "$REGEN_LOG" 2>&1 &
fi
