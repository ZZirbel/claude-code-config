# Windows Hooks Maintenance Guide

This document describes how to maintain Windows PowerShell hook scripts when syncing updates from the upstream repository.

## Background

The upstream repo (`aaronsb/claude-code-config`) uses bash scripts for hooks. This fork adds PowerShell equivalents for Windows compatibility.

### Script Mapping

| Bash Script (upstream) | PowerShell Script (this fork) |
|------------------------|-------------------------------|
| `hooks/check-config-updates.sh` | `hooks/check-config-updates.ps1` |
| `hooks/refresh-claude-md.sh` | `hooks/refresh-claude-md.ps1` |

### Configuration File

| File | Upstream | This Fork |
|------|----------|-----------|
| `hooks/hooks.json` | Uses `cat` and bash scripts | Uses `powershell.exe` and PS1 scripts |

## Sync Procedure

### 1. Fetch upstream changes

```bash
cd ~/.claude
git fetch origin
git log HEAD..origin/main --oneline
```

### 2. Check if bash hook scripts changed

```bash
git diff HEAD..origin/main -- hooks/check-config-updates.sh hooks/refresh-claude-md.sh hooks/hooks.json
```

### 3. If bash scripts changed, update PowerShell equivalents

**Before merging**, review the changes to bash scripts and manually update the corresponding PowerShell scripts to match the new functionality.

#### Key translation patterns:

| Bash | PowerShell |
|------|------------|
| `$HOME` | `$env:USERPROFILE` |
| `$(date +%s)` | `[int][double]::Parse((Get-Date -UFormat %s))` |
| `cat file` | `Get-Content file` |
| `touch file` | `(Get-Item file).LastWriteTime = Get-Date` |
| `[ -f file ]` | `Test-Path file` |
| `[ -d dir ]` | `Test-Path dir` |
| `echo "text" > file` | `"text" \| Out-File file` |
| `command -v cmd` | `Get-Command cmd -ErrorAction SilentlyContinue` |
| `exit 0` | `exit 0` |

### 4. Merge upstream changes

```bash
git merge origin/main
```

### 5. If hooks.json was overwritten, restore Windows version

Check if hooks.json still uses PowerShell:

```bash
cat hooks/hooks.json | grep powershell
```

If not found, restore the Windows-compatible version:

```json
{
  "description": "Injects methodology instructions at critical moments and checks for updates (Windows-compatible)",
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "powershell.exe -NoProfile -Command \"Get-Content \\\"$env:USERPROFILE\\.claude\\claude-hook.md\\\"\""
      },
      {
        "type": "command",
        "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"$env:USERPROFILE\\.claude\\hooks\\check-config-updates.ps1\""
      }
    ],
    "PreCompact": [
      {
        "type": "command",
        "command": "powershell.exe -NoProfile -Command \"Get-Content \\\"$env:USERPROFILE\\.claude\\claude-hook.md\\\"\""
      }
    ]
  }
}
```

### 6. Test the updated hooks

```powershell
# Test methodology injection
powershell.exe -NoProfile -Command 'Get-Content "$env:USERPROFILE\.claude\claude-hook.md"' | Select-Object -First 10

# Test update checker
Remove-Item "$env:USERPROFILE\.claude\.last-plugin-update-check" -ErrorAction SilentlyContinue
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\check-config-updates.ps1"

# Test refresh script
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\hooks\refresh-claude-md.ps1"
```

### 7. Commit the updates

```bash
cd ~/.claude
git add hooks/*.ps1 hooks/hooks.json
git commit -m "feat: Update PowerShell hooks to match upstream bash changes"
git push origin main
```

## Quick Reference Commands

### Sync from upstream (full process)

```bash
cd ~/.claude

# 1. Check for upstream changes
gh repo sync ZZirbel/claude-code-config --source aaronsb/claude-code-config

# 2. Pull changes
git pull origin main

# 3. Check if hooks need updating
git log -1 --name-only | grep -E "hooks/.*\.sh|hooks/hooks.json"

# 4. If yes, update PS1 files and hooks.json, then commit
```

### Check current sync status

```bash
gh api repos/ZZirbel/claude-code-config/compare/main...aaronsb:claude-code-config:main --jq '.status, .ahead_by, .behind_by'
```

## Troubleshooting

### Hooks not running
- Verify `hooks/hooks.json` uses PowerShell commands (not bash)
- Check PowerShell execution policy: `Get-ExecutionPolicy`
- Test scripts manually to see errors

### Environment variables not expanding
- Use `$env:USERPROFILE` (not `$HOME`) in PowerShell
- Ensure proper escaping in JSON: `\\` for single backslash

### Scripts fail silently
- Run scripts directly in PowerShell to see error output
- Check for path issues (forward vs back slashes)
