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

- **`settings.windows.json`** - PowerShell-based hook configuration (template)
- **`hooks/ways/win/*.ps1`** - PowerShell equivalents of all bash hook scripts
- **`hooks/check-config-updates.ps1`** - PowerShell port of config update checker

## Upstream Sync & Refactoring

This fork syncs from `aaronsb/claude-code-config` (upstream). When pulling upstream changes:

1. **Add upstream remote**: `git remote add upstream https://github.com/aaronsb/claude-code-config.git`
2. **Fetch and merge**: `git fetch upstream && git merge upstream/main`
3. **For script changes**: See `pc-refactor.md` for bash-to-PowerShell transformation patterns
4. **Regenerate settings**: `New-ClaudeSettings -Force` (after any `settings.windows.json` changes)

### Key Refactoring Rules

- Upstream bash hooks live in `hooks/ways/*.sh` — keep in sync
- PowerShell equivalents go in `hooks/ways/win/*.ps1`
- Most hook scripts are now thin dispatchers to the `ways` binary
- `settings.windows.json` is the template (uses `-Command` with `$env:USERPROFILE`)
- `settings.json` is generated locally by `New-ClaudeSettings` (resolves paths for bash)
- See `pc-refactor.md` for the complete transformation pattern reference

## Config Management

Single-account config managed via `ClaudeConfigManager.psm1`:
- `ccstatus` — show config health, git status, commits behind
- `ccupdate` — pull latest from fork
- `ccinstall` — bootstrap on new device (clone + generate settings)
- `New-ClaudeSettings -Force` — regenerate `settings.json` from template
