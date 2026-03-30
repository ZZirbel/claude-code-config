# ADR-111 Phase 3: ways CLI — Session State + Diagnostics

**Branch:** `staging/ADR-111`
**Status:** 59 commits, 19 subcommands, 8 integration tests, all passing.

## This session's work (commits 42-59)

### Integration tests + CI
- Session simulator: 8 scenarios covering matching, idempotency, commands, files, checks, progressive disclosure, scope, epochs
- Cross-compilation CI: GitHub Actions for 4 platforms (linux-x86_64/aarch64, darwin-x86_64/arm64)
- `make test-sim`, `make release` targets

### Governance consolidation
- `governance.sh` (543 lines) → `ways governance` (9 modes, --json, --global)
- Refactored `provenance.rs` with public `generate_manifest()` API

### Matching engine fix
- **Embedding-primary matching**: when embed is available, BM25 is fallback only
- Previously 84 BM25 vs 8 embed matches; now embed is sole semantic authority
- This is a significant behavioral improvement in match precision

### Project-scoped commands
- `ways stats`, `ways lint`, `ways governance`: detect project from cwd, `--global` to bypass
- Project detection: walks up from `$PWD` looking for `.claude/settings.json` or `CLAUDE.md`

### New commands
- `ways context`: accurate token counts from transcript API data, model detection
- `ways reset`: session state recovery, dry-run default, `--confirm` to execute
- `ways lint --fix`: auto-fix multi-line YAML, missing check sections

### Enhanced `ways list`
- Epoch-ordered table with distance, trigger channel, check decay
- Colored pin symbols (⌖ column) linking table rows to forecast bar
- Zoomed forecast bar showing re-disclosure timeline with token scale
- Zone summary: ● now / ◐ approaching / ○ distant
- `--sort=epoch|name|distance`, `--json`

### Shared table formatter
- `table.rs`: column alignment, ANSI-aware truncation, width caps
- Retrofitted: `tree`, `match`, `siblings` commands

### Directory-per-session state (major refactor)
- `/tmp/.claude-sessions/{session_id}/` replaces flat `/tmp/.claude-*-{uuid}` markers
- Way IDs are real paths now — no more dash-encoding or filesystem disambiguation
- Cleanup is `rm -rf` one directory — no cross-session contamination
- Fixed: clear-markers.sh was globally nuking all sessions on any SessionStart

### Schema fix
- Added `when` block (project, file_exists) to check section in frontmatter-schema.yaml
- Fixed 2 persistent lint warnings on makefile.check.md

## What's next

### Code review pass
- `governance.rs` at 896 lines — split into module directory (like scan/, show/)
- `lint.rs` at 614, `list.rs` at 581, `session.rs` at 546 — review for splits
- Check for dead code from the session state refactor (old flat-marker patterns)
- Verify all `scan/mod.rs` paths use new session directory structure

### Cross-compilation + release packaging
- The CI workflow exists but hasn't been tested against GitHub Actions
- `make release` works locally; need to verify zigbuild for ARM cross-compile
- Consider: should `governance.sh` and `provenance-verify.sh` be deleted now?
- Binary size check after all additions (was 3.1MB, now 3.6MB)

### Remaining absorptions (lower priority)
- `scripts/context-usage.sh` → already superseded by `ways context` (can delete)
- `governance.sh` → already superseded by `ways governance` (can delete)
- Smart trigger redesign (old script was deleted as broken)

### Ship PRs
- `staging/ADR-111` → `main` (57 commits, consider squash strategy)

## How to resume

```bash
git checkout staging/ADR-111
cat .claude/todo-ADR-111-phase2.md
make test && make test-sim
ways list
ways context
```

The ways binary is LIVE — hooks fire against it every message.
Session state now in `/tmp/.claude-sessions/{session_id}/` (directory tree).
All 8 simulation tests pass. Lint: 0 errors, 0 warnings.
