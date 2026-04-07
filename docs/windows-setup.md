# Windows Setup Guide

This guide walks you through setting up claude-code-config on Windows with full PowerShell support.

## Prerequisites

- **Windows 10/11** (64-bit)
- **PowerShell 5.1+** (included with Windows)
- **Git for Windows** (includes Git Bash)
- **GitHub CLI** (`gh`) — required for `make setup` to download the `ways` binary
- **Claude Code CLI** (`npm install -g @anthropic-ai/claude-code`)

### Optional

- **GNU make** — required for `make setup` / `make update` workflow (see [Installing make](#installing-make))
- **Pester** — for running tests (`Install-Module Pester -Force`)

## Installing make

`make` is required to run `make setup` and `make update` as documented in the CLAUDE.md workflow.

**Recommended: GnuWin32 via winget**

```powershell
winget install GnuWin32.Make
```

This installs make to `C:\Program Files (x86)\GnuWin32\bin`. Add it to your Git Bash PATH permanently by adding this line to `~/.bashrc`:

```bash
export PATH="$PATH:/c/Program Files (x86)/GnuWin32/bin"
```

> **Note:** The GnuWin32 path contains spaces and parentheses. This works for top-level `make` targets (`make setup`, `make ways`, `make update`) but breaks the optional embedding engine step (`make -C tools/way-embed setup`) due to a recursive make path expansion issue. The core `ways` binary and corpus generation work correctly. See [Embedding Engine](#embedding-engine) below.

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

#### Step 4: Generate settings

```powershell
cd "$env:USERPROFILE\.claude"
# The ClaudeConfigManager module generates settings.json from the Windows template
Import-Module .\scripts\ClaudeConfigManager.psm1
New-ClaudeSettings -Force
```

#### Step 5: Install the ways binary

From Git Bash:

```bash
cd ~/.claude && make setup
# or without make:
bash tools/ways-cli/download-ways.sh
bin/ways.exe corpus --quiet
```

#### Step 6: Verify installation

```powershell
# Binary works
& "$env:USERPROFILE\.claude\bin\ways.exe" --version

# Corpus generated
Test-Path "$env:LOCALAPPDATA\claude-ways\user\ways-corpus.jsonl"

# Hooks exist
(Get-ChildItem "$env:USERPROFILE\.claude\hooks\ways\win\*.ps1").Count
```

### Option B: Copy Approach (No Admin Required)

If you can't create symlinks, copy the repo contents to `~/.claude`:

```powershell
git clone https://github.com/ZZirbel/claude-code-config "$env:TEMP\claude-code-config"
robocopy "$env:TEMP\claude-code-config" "$env:USERPROFILE\.claude" /MIR /XD .git
Import-Module "$env:USERPROFILE\.claude\scripts\ClaudeConfigManager.psm1"
New-ClaudeSettings -Force
Remove-Item -Recurse -Force "$env:TEMP\claude-code-config"
```

Then follow Steps 5–6 from Option A.

**Note:** With this approach, run `ccupdate` to sync future updates.

## Configuration

### Settings Management

Settings are managed via `ClaudeConfigManager.psm1`:

| Command | Purpose |
|---------|---------|
| `New-ClaudeSettings -Force` | Regenerate `settings.json` from `settings.windows.json` template |
| `ccstatus` | Show config health and git status |
| `ccupdate` | Pull latest changes and regenerate settings |

`settings.windows.json` is the source of truth — it uses `$env:USERPROFILE` placeholders. `New-ClaudeSettings` resolves these to absolute paths and writes `settings.json`.

### Disabling Specific Way Domains

Edit `ways.json` to disable domains you don't need:

```json
{
  "disabled": ["itops", "ea"]
}
```

## Updating

```powershell
Import-Module "$env:USERPROFILE\.claude\scripts\ClaudeConfigManager.psm1"
ccupdate
```

`ccupdate` pulls from origin, regenerates `settings.json`, and re-runs `ways corpus`. If the upstream sync workflow has created a pending PR (script changes requiring PowerShell porting), review it before merging.

## Embedding Engine

The embedding engine improves matching accuracy from 91% (BM25) to 98% (semantic). It is optional — the system works fully without it.

Installing it requires `make -C tools/way-embed setup`, which currently fails on Windows when `make` is installed via GnuWin32 (path-with-spaces issue). Workaround options:

1. **Accept BM25** (91% accuracy) — adequate for most use cases
2. **Install make via MSYS2** — places make in a clean path (`C:\msys64\usr\bin\make.exe`)
3. **Track**: ZZirbel/claude-code-config#3 — Windows embedding engine support is a tracked improvement

## Verifying the Installation

### Quick Smoke Test

From Git Bash:

```bash
cd ~/.claude

# 1. Binary runs
bin/ways.exe --version

# 2. Matching works
bin/ways.exe match "write a unit test"

# 3. Corpus is present
bin/ways.exe corpus --if-stale --quiet && echo "corpus OK"
```

### Full Test Suite

```powershell
Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0
Invoke-Pester -Path .\tests\pester -Output Detailed
```

## Troubleshooting

### `ways` binary not found / hooks inactive at startup

Run setup:

```bash
# From Git Bash in ~/.claude
bash tools/ways-cli/download-ways.sh
bin/ways.exe corpus --quiet
```

The `check-setup.ps1` hook emits a warning at session start if the binary is missing. Once installed the warning stops.

### "Cannot create symbolic link" error

You need Administrator privileges for symlinks. Either:
1. Run PowerShell as Administrator
2. Use Option B (Copy Approach)
3. Enable Developer Mode in Windows Settings (allows symlinks without admin)

### "Execution policy prevents running scripts"

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Hooks not firing

1. Verify `settings.json` contains PowerShell hooks:
   ```powershell
   Get-Content settings.json | Select-String "powershell.exe"
   # Should show matches
   ```

2. Regenerate settings if needed:
   ```powershell
   Import-Module .\scripts\ClaudeConfigManager.psm1
   New-ClaudeSettings -Force
   ```

3. Test a hook manually:
   ```powershell
   '{"prompt":"test","session_id":"test"}' | & hooks/ways/win/check-prompt.ps1
   ```

### make: command not found

Install GnuWin32 make and add to Git Bash PATH:

```bash
# Add to ~/.bashrc
export PATH="$PATH:/c/Program Files (x86)/GnuWin32/bin"
```

## File Structure After Installation

```
~/.claude/
├── settings.json              (generated by New-ClaudeSettings)
├── settings.windows.json      (PowerShell hooks template — source of truth)
├── ways.json                  (domain enable/disable config)
├── CLAUDE.md                  (project instructions)
├── pc-refactor.md             (bash→PowerShell refactoring patterns)
├── bin/
│   └── ways.exe               (ways CLI binary — downloaded by make setup)
├── hooks/
│   ├── check-config-updates.ps1
│   └── ways/
│       ├── *.sh               (bash scripts — upstream reference)
│       ├── win/               (PowerShell equivalents)
│       │   ├── check-prompt.ps1
│       │   ├── check-bash-pre.ps1
│       │   ├── check-file-pre.ps1
│       │   ├── check-setup.ps1
│       │   ├── check-state.ps1
│       │   ├── check-task-pre.ps1
│       │   ├── check-response.ps1
│       │   ├── clear-markers.ps1
│       │   ├── inject-subagent.ps1
│       │   ├── mark-tasks-active.ps1
│       │   └── require-ways.ps1
│       ├── core.md            (base guidance)
│       ├── softwaredev/       (software dev ways)
│       ├── meta/              (system ways)
│       └── itops/             (IT ops ways)
├── scripts/
│   └── ClaudeConfigManager.psm1
├── tests/
│   └── pester/                (PowerShell tests)
├── tools/
│   └── ways-cli/
│       └── download-ways.sh   (binary download script)
└── docs/
    └── windows-setup.md       (this file)
```

## Getting Help

- **Repository Issues**: https://github.com/ZZirbel/claude-code-config/issues
- **Upstream Documentation**: https://github.com/aaronsb/claude-code-config
- **Claude Code Docs**: https://docs.anthropic.com/claude-code
