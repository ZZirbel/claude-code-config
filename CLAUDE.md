# ADR-Driven Development Config

ADR-driven workflow with GitHub-first collaboration.

**Instructions are injected via hooks, not this file.**

Instructions are loaded at critical moments to maintain relevance:
- **SessionStart** - Fresh context when sessions begin
- **PreCompact** - Fresh context after compaction events

This approach ensures guidance stays active in the conversation window rather than being buried as distant system prompts.

See `hooks/ways/core.md` for the base guidance and `hooks/ways/*.md` for contextual instructions.

## Windows/PC Configuration

This fork includes full Windows PowerShell support. Key files:

- **`settings.windows.json`** - PowerShell-based hook configuration (copy to `settings.json` to activate)
- **`hooks/ways/win/*.ps1`** - PowerShell equivalents of all bash hook scripts
- **`docs/windows-setup.md`** - Complete Windows installation guide

## Upstream Sync & Refactoring

This fork syncs from `aaronsb/claude-code-config` (upstream). When pulling upstream changes:

1. **Run the sync script**: `.\scripts\Sync-Upstream.ps1`
2. **For complex changes**: See `pc-refactor.md` for bash-to-PowerShell transformation patterns
3. **Run tests**: `Invoke-Pester -Path .\tests\pester`

### Automated Sync

GitHub Actions automatically:
- Checks for upstream changes daily
- Creates PRs for new changes
- Auto-merges data-only changes (ways, docs)
- Flags script changes for manual PowerShell porting

See `.github/workflows/upstream-sync.yml` for the pipeline configuration.
