# ADR-111 Phase 3: ways CLI — Code Review + Cleanup

**Branch:** `staging/ADR-111`
**Status:** 19 subcommands, 8 integration tests, 0 warnings, all passing.

## This session's work

### Code review pass (done)
- Split `governance.rs` (896 lines) → 7-file module directory (largest: 164 lines)
- Fixed all 6 cargo warnings (unused imports, dead fields, dead code)
- Removed dead `marker_name()` from session.rs (flat-marker era leftover)

### Deleted superseded scripts (done)
- `governance/governance.sh` (543 lines) → `ways governance`
- `governance/provenance-verify.sh` → `ways governance lint`
- `scripts/context-usage.sh` → `ways context`

### Updated all functional references (done)
- `commands/governance.md` — now references `ways governance`
- `skills/governance-cite/SKILL.md` — all commands updated
- `skills/context-status/SKILL.md` — now uses `ways context`
- `hooks/ways/meta/*/macro.sh` (3 files) — now call `ways context`
- `hooks/ways/meta/knowledge/optimization/macro.sh` — now calls `ways suggest`
- `tests/run-all.sh` — governance test uses `ways governance lint`
- `tests/README.md` — updated commands and test layers
- `README.md` — updated governance reference
- `governance/README.md` — complete rewrite for `ways` CLI
- `docs/governance.md` — updated tools section, diagrams, references
- `docs/hooks-and-ways.md` — updated pipeline description, diagrams, all script references
- `docs/hooks-and-ways/macros.md` — updated show-core.sh reference
- `docs/hooks-and-ways/provenance.md` — updated commands
- `docs/architecture.md` — updated 5 Mermaid diagrams, file tree listing
- `hooks/ways/frontmatter-schema.yaml` — updated comment
- `hooks/check-config-updates.sh` — updated stale comment
- `hooks/ways/check-task-pre.sh` — removed historical comment
- `skills/ways-tests/SKILL.md` — updated metrics path
- Way files: optimization.md, diagrams.md, release.md — updated references

### Reviewed large files (done, no splits needed)
- `lint.rs` (614), `list.rs` (638), `session.rs` (538), `scan/mod.rs` (542)
- All have clear internal structure, none above 800-line priority threshold
- Only governance.rs needed splitting

### .gitignore
- Removed `scripts/context-usage.sh` exception (script deleted)

## What's next

1. **Cross-compilation CI** — test the GitHub Actions workflow, verify zigbuild ARM builds
2. **Binary size check** — was 3.6MB, verify after governance split (should be unchanged)
3. **Ship PR** — `staging/ADR-111` → `main` (discuss squash strategy)

## How to resume

```bash
git checkout staging/ADR-111
cat .claude/todo-ADR-111-phase2.md
make test && make test-sim
ways governance report
```

The ways binary is LIVE — hooks fire against it every message.
Session state in `/tmp/.claude-sessions/{session_id}/` (directory tree).
All 8 simulation tests pass. Lint: 0 errors, 0 warnings. 0 cargo warnings.
