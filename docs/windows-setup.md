# Windows Setup Guide

This guide walks you through setting up claude-code-config on Windows with full PowerShell support.

## Prerequisites

- **Windows 10/11** (64-bit)
- **PowerShell 5.1+** (included with Windows)
- **Git for Windows** (includes Git Bash)
- **Claude Code CLI** (`npm install -g @anthropic-ai/claude-code`)

### Optional but Recommended

- **GitHub CLI** (`gh`) for PR automation
- **Pester** for running tests (`Install-Module Pester -Force`)

## Installation Options

### Option A: Symlink Approach (Recommended)

This approach makes `~/.claude` a symlink to your git repository, allowing seamless `git pull` updates.

#### Step 1: Backup existing config (if any)

```powershell
if (Test-Path "$env:USERPROFILE\.claude") {
    Move-Item "$env:USERPROFILE\.claude" "$env:USERPROFILE\.claude-backup-$(Get-Date -Format 'yyyyMMdd')"
    Write-Host "Existing config backed up"
}
```

#### Step 2: Clone the repository

```powershell
git clone https://github.com/ZZirbel/claude-code-config "$env:USERPROFILE\GitHub\claude-code-config"
```

#### Step 3: Create symlink (requires Administrator)

Open PowerShell as Administrator:

```powershell
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.claude" -Target "$env:USERPROFILE\GitHub\claude-code-config"
```

#### Step 4: Activate Windows settings

```powershell
cd "$env:USERPROFILE\.claude"
Copy-Item "settings.windows.json" "settings.json" -Force
Write-Host "Windows PowerShell hooks activated"
```

#### Step 5: Verify installation

```powershell
# Test binary
./bin/way-match --version

# Test hooks directory
Test-Path "$env:USERPROFILE\.claude\hooks\ways\win"

# Run tests
Install-Module Pester -Force -Scope CurrentUser
Invoke-Pester -Path .\tests\pester -Output Minimal
```

### Option B: Copy Approach (No Admin Required)

If you can't create symlinks, copy the repo contents to `~/.claude`:

```powershell
# Clone to temp location
git clone https://github.com/ZZirbel/claude-code-config "$env:TEMP\claude-code-config"

# Copy to .claude (preserving your existing settings if any)
robocopy "$env:TEMP\claude-code-config" "$env:USERPROFILE\.claude" /MIR /XD .git

# Copy Windows settings
Copy-Item "$env:USERPROFILE\.claude\settings.windows.json" "$env:USERPROFILE\.claude\settings.json" -Force

# Cleanup
Remove-Item -Recurse -Force "$env:TEMP\claude-code-config"
```

**Note:** With this approach, you'll need to manually sync updates.

## Configuration

### Activating Windows PowerShell Hooks

The repository includes two settings files:
- `settings.json` - Bash-based hooks (default, for Unix)
- `settings.windows.json` - PowerShell-based hooks (for Windows)

To use PowerShell hooks, copy the Windows settings:

```powershell
Copy-Item "$env:USERPROFILE\.claude\settings.windows.json" "$env:USERPROFILE\.claude\settings.json" -Force
```

### Disabling Specific Way Domains

Edit `ways.json` to disable domains you don't need:

```json
{
  "disabled": ["itops", "ea"]
}
```

### Customizing Ways

Create project-specific ways in your project's `.claude/ways/` directory:

```powershell
# In your project root
mkdir -p .claude/ways/custom
```

## Updating

### With Symlink Setup

```powershell
cd "$env:USERPROFILE\.claude"
git pull origin main

# If upstream has changes
.\scripts\Sync-Upstream.ps1
```

### With Copy Setup

```powershell
# Re-clone and copy
git clone https://github.com/ZZirbel/claude-code-config "$env:TEMP\claude-code-config"
robocopy "$env:TEMP\claude-code-config" "$env:USERPROFILE\.claude" /MIR /XD .git /XF settings.json ways.json
Remove-Item -Recurse -Force "$env:TEMP\claude-code-config"
```

## Scheduled Auto-Updates (Optional)

Create a scheduled task to check for updates daily:

```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument @"
-NoProfile -ExecutionPolicy Bypass -Command "
Set-Location '$env:USERPROFILE\.claude'
git fetch origin main
\$behind = git rev-list HEAD..origin/main --count
if (\$behind -gt 0) {
    Write-Host 'Updates available: ' + \$behind + ' commits behind'
}
"
"@

$trigger = New-ScheduledTaskTrigger -Daily -At 9am

Register-ScheduledTask -TaskName "Claude Config Update Check" -Action $action -Trigger $trigger -Description "Check for claude-code-config updates"
```

## Verifying the Installation

### Quick Smoke Test

```powershell
# 1. Binary works
./bin/way-match pair --description "test" --vocabulary "test" --query "test" --threshold 0.1
# Should exit 0 (match) or 1 (no match), not error

# 2. Settings are valid
Get-Content settings.json | ConvertFrom-Json | Out-Null
# Should not error

# 3. PowerShell hooks exist
(Get-ChildItem hooks/ways/win/*.ps1).Count
# Should show 10+ scripts
```

### Full Test Suite

```powershell
Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0
Invoke-Pester -Path .\tests\pester -Output Detailed
```

## Troubleshooting

### "Cannot create symbolic link" Error

You need Administrator privileges for symlinks. Either:
1. Run PowerShell as Administrator
2. Use Option B (Copy Approach)
3. Enable Developer Mode in Windows Settings (allows symlinks without admin)

### "Execution policy prevents running scripts"

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### "way-match binary not found or won't run"

The APE binary should work on Windows, but may need adjustments:

```powershell
# Try with explicit path
& "$env:USERPROFILE\.claude\bin\way-match" --version

# If that fails, the APE may need .exe extension
Copy-Item "$env:USERPROFILE\.claude\bin\way-match" "$env:USERPROFILE\.claude\bin\way-match.exe"
```

### Hooks not firing

1. Verify settings.json is the Windows version:
   ```powershell
   Get-Content settings.json | Select-String "powershell.exe"
   # Should show matches
   ```

2. Check Claude Code is using your config:
   ```powershell
   claude --version
   # Verify it's picking up ~/.claude
   ```

3. Test a hook manually:
   ```powershell
   '{"prompt":"test","session_id":"test"}' | & hooks/ways/win/check-prompt.ps1
   ```

### Git Bash vs PowerShell conflicts

If you have Git Bash, some commands might use bash instead of PowerShell. The hooks are designed to use PowerShell directly via `settings.windows.json`. Make sure you're using the Windows settings file.

## File Structure After Installation

```
~/.claude/
├── settings.json          (copy of settings.windows.json)
├── settings.windows.json  (PowerShell hooks config)
├── ways.json              (domain enable/disable config)
├── CLAUDE.md              (project instructions)
├── pc-refactor.md         (refactoring instructions for Claude)
├── bin/
│   └── way-match          (BM25 matching binary)
├── hooks/
│   └── ways/
│       ├── *.sh           (bash scripts - reference)
│       ├── win/           (PowerShell equivalents)
│       │   ├── check-prompt.ps1
│       │   ├── check-bash-pre.ps1
│       │   └── ...
│       ├── core.md        (base guidance)
│       ├── softwaredev/   (software dev ways)
│       ├── meta/          (system ways)
│       └── itops/         (IT ops ways)
├── scripts/
│   └── Sync-Upstream.ps1  (upstream sync script)
├── tests/
│   └── pester/            (PowerShell tests)
└── docs/
    └── windows-setup.md   (this file)
```

## Getting Help

- **Repository Issues**: https://github.com/ZZirbel/claude-code-config/issues
- **Upstream Documentation**: https://github.com/aaronsb/claude-code-config
- **Claude Code Docs**: https://docs.anthropic.com/claude-code
