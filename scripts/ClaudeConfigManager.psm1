#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code configuration manager

.DESCRIPTION
    Manages the Claude Code configuration directory (~/.claude/):
    - Status: git status, commits behind upstream, health checks
    - Update: pull latest config from your fork
    - Bootstrap: clone config to a new device and apply settings

.NOTES
    Add to your PowerShell profile:
    Import-Module "$env:USERPROFILE\.claude\scripts\ClaudeConfigManager.psm1"
#>

# ============================================================================
# Configuration
# ============================================================================

$script:ConfigDir = "$env:USERPROFILE\.claude"
$script:RepoUrl = "git@github.com:ZZirbel/claude-code-config.git"
$script:RepoHttpsUrl = "https://github.com/ZZirbel/claude-code-config.git"

# ============================================================================
# Helper Functions
# ============================================================================

function Get-ShortCommitHash {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "unknown" }
    Push-Location $Path
    try {
        $hash = git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { return $hash }
        return "unknown"
    } catch {
        return "unknown"
    } finally {
        Pop-Location
    }
}

function Get-CommitDate {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return "unknown" }
    Push-Location $Path
    try {
        $date = git log -1 --format="%cs" 2>$null
        if ($LASTEXITCODE -eq 0) { return $date }
        return "unknown"
    } catch {
        return "unknown"
    } finally {
        Pop-Location
    }
}

function Get-CommitsBehind {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return -1 }
    Push-Location $Path
    try {
        git fetch origin main 2>$null | Out-Null
        $behind = git rev-list HEAD..origin/main --count 2>$null
        if ($LASTEXITCODE -eq 0) { return [int]$behind }
        return -1
    } catch {
        return -1
    } finally {
        Pop-Location
    }
}

function Test-IsGitRepo {
    param([string]$Path)
    return (Test-Path (Join-Path $Path ".git"))
}

function Get-ConfigRemoteUrl {
    if (-not (Test-Path $script:ConfigDir)) { return $null }
    Push-Location $script:ConfigDir
    try {
        $url = git remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0) { return $url }
        return $null
    } catch {
        return $null
    } finally {
        Pop-Location
    }
}

# ============================================================================
# Public Functions
# ============================================================================

function Get-ClaudeConfigStatus {
    <#
    .SYNOPSIS
        Shows the status of Claude Code configuration

    .DESCRIPTION
        Displays health and sync status:
        - Config directory existence and git status
        - Current commit and date
        - Commits behind upstream
        - Key files present (settings.json, CLAUDE.md, hooks/)
        - Remote URL validation

    .PARAMETER Quiet
        Return status object instead of formatted output

    .EXAMPLE
        Get-ClaudeConfigStatus

    .EXAMPLE
        ccstatus
    #>
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    $status = @{
        ConfigDir     = $script:ConfigDir
        Exists        = Test-Path $script:ConfigDir
        IsGitRepo     = $false
        Commit        = "N/A"
        CommitDate    = "N/A"
        Behind        = 0
        RemoteUrl     = $null
        RemoteCorrect = $false
        HasSettings   = $false
        HasClaudeMd   = $false
        HasHooks      = $false
        HasAgents     = $false
        Issues        = @()
    }

    if ($status.Exists) {
        $status.IsGitRepo = Test-IsGitRepo $script:ConfigDir
        $status.HasSettings = Test-Path (Join-Path $script:ConfigDir "settings.json")
        $status.HasClaudeMd = Test-Path (Join-Path $script:ConfigDir "CLAUDE.md")
        $status.HasHooks = Test-Path (Join-Path $script:ConfigDir "hooks")
        $status.HasAgents = Test-Path (Join-Path $script:ConfigDir "agents")

        if ($status.IsGitRepo) {
            $status.Commit = Get-ShortCommitHash $script:ConfigDir
            $status.CommitDate = Get-CommitDate $script:ConfigDir
            $status.Behind = Get-CommitsBehind $script:ConfigDir
            $status.RemoteUrl = Get-ConfigRemoteUrl

            # Check if remote points to user's fork
            $status.RemoteCorrect = ($status.RemoteUrl -eq $script:RepoUrl) -or
                                    ($status.RemoteUrl -eq $script:RepoHttpsUrl)
        }

        # Identify issues
        if (-not $status.IsGitRepo) { $status.Issues += "Not a git repository" }
        if (-not $status.HasSettings) { $status.Issues += "Missing settings.json" }
        if (-not $status.HasHooks) { $status.Issues += "Missing hooks directory" }
        if (-not $status.RemoteCorrect -and $status.IsGitRepo) {
            $status.Issues += "Remote points to '$($status.RemoteUrl)' (expected ZZirbel/claude-code-config)"
        }
    } else {
        $status.Issues += "Config directory not found"
    }

    if ($Quiet) {
        return [PSCustomObject]$status
    }

    # Formatted output
    Write-Host ""
    Write-Host "  Claude Code Config Status" -ForegroundColor White
    Write-Host "  =========================" -ForegroundColor DarkGray
    Write-Host ""

    if (-not $status.Exists) {
        Write-Host "  Config: " -NoNewline
        Write-Host "NOT FOUND" -ForegroundColor Red
        Write-Host "  Expected: $script:ConfigDir" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Run: " -NoNewline -ForegroundColor DarkGray
        Write-Host "Install-ClaudeConfig" -ForegroundColor Cyan -NoNewline
        Write-Host " to set up" -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # Git status
    if ($status.IsGitRepo) {
        $syncStatus = if ($status.Behind -eq 0) { "Up to date" }
                      elseif ($status.Behind -gt 0) { "$($status.Behind) update(s) behind" }
                      else { "Error checking" }
        $syncColor = if ($status.Behind -eq 0) { "Green" }
                     elseif ($status.Behind -gt 0) { "Yellow" }
                     else { "Red" }

        Write-Host "  Commit:  " -NoNewline -ForegroundColor DarkGray
        Write-Host $status.Commit -ForegroundColor Cyan -NoNewline
        Write-Host " ($($status.CommitDate))" -ForegroundColor DarkGray

        Write-Host "  Status:  " -NoNewline -ForegroundColor DarkGray
        Write-Host $syncStatus -ForegroundColor $syncColor

        Write-Host "  Remote:  " -NoNewline -ForegroundColor DarkGray
        if ($status.RemoteCorrect) {
            Write-Host "ZZirbel/claude-code-config" -ForegroundColor Green
        } else {
            Write-Host $status.RemoteUrl -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Git:     " -NoNewline -ForegroundColor DarkGray
        Write-Host "Not a git repository" -ForegroundColor Red
    }

    Write-Host "  Path:    " -NoNewline -ForegroundColor DarkGray
    Write-Host $script:ConfigDir -ForegroundColor DarkGray

    # Key files
    Write-Host ""
    Write-Host "  Files:" -ForegroundColor White

    $files = @(
        @{ Name = "settings.json"; Present = $status.HasSettings }
        @{ Name = "CLAUDE.md";     Present = $status.HasClaudeMd }
        @{ Name = "hooks/";        Present = $status.HasHooks }
        @{ Name = "agents/";       Present = $status.HasAgents }
    )

    foreach ($f in $files) {
        $icon = if ($f.Present) { "[OK]" } else { "[!!]" }
        $color = if ($f.Present) { "Green" } else { "Yellow" }
        Write-Host "    $icon $($f.Name)" -ForegroundColor $color
    }

    # Issues and suggestions
    if ($status.Issues.Count -gt 0) {
        Write-Host ""
        Write-Host "  Issues:" -ForegroundColor Yellow
        foreach ($issue in $status.Issues) {
            Write-Host "    - $issue" -ForegroundColor Yellow
        }
    }

    if ($status.Behind -gt 0) {
        Write-Host ""
        Write-Host "  Run: " -NoNewline -ForegroundColor DarkGray
        Write-Host "Update-ClaudeConfig" -ForegroundColor Cyan -NoNewline
        Write-Host " to pull latest" -ForegroundColor DarkGray
    }

    if (-not $status.RemoteCorrect -and $status.IsGitRepo) {
        Write-Host "  Run: " -NoNewline -ForegroundColor DarkGray
        Write-Host "Install-ClaudeConfig" -ForegroundColor Cyan -NoNewline
        Write-Host " to fix remote" -ForegroundColor DarkGray
    }

    Write-Host ""
}

function Update-ClaudeConfig {
    <#
    .SYNOPSIS
        Updates Claude Code configuration from git

    .DESCRIPTION
        Pulls the latest config from your fork. If ~/.claude/ doesn't exist
        or isn't a git repo, suggests running Install-ClaudeConfig instead.

    .PARAMETER Force
        Discard local changes before pulling

    .EXAMPLE
        Update-ClaudeConfig

    .EXAMPLE
        ccupdate -Force
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    if (-not (Test-Path $script:ConfigDir)) {
        Write-Host "Config directory not found at $script:ConfigDir" -ForegroundColor Red
        Write-Host "Run: Install-ClaudeConfig" -ForegroundColor Yellow
        return
    }

    if (-not (Test-IsGitRepo $script:ConfigDir)) {
        Write-Host "Config directory is not a git repository" -ForegroundColor Red
        Write-Host "Run: Install-ClaudeConfig" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Updating Claude Code config..." -ForegroundColor Cyan
    Write-Host "  Path: $script:ConfigDir" -ForegroundColor DarkGray

    Push-Location $script:ConfigDir
    try {
        # settings.json is always generated from the template, so it will
        # always show as modified. Restore it before pulling to avoid conflicts,
        # then regenerate after.
        $settingsModified = git diff --name-only 2>$null | Where-Object { $_ -eq "settings.json" }
        if ($settingsModified) {
            git checkout -- settings.json 2>&1 | Out-Null
        }

        # Check for other local changes (excluding the generated settings.json)
        $changes = git status --porcelain 2>$null
        if ($changes -and -not $Force) {
            Write-Host "  Local changes detected:" -ForegroundColor Yellow
            $changes | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            Write-Host "  Use -Force to discard, or commit them first" -ForegroundColor Yellow
            return
        }

        if ($Force -and $changes) {
            Write-Host "  Discarding local changes..." -ForegroundColor Yellow
            git reset --hard HEAD 2>&1 | Out-Null
        }

        # Pull latest
        Write-Host "  Pulling latest..." -ForegroundColor DarkGray
        $pullResult = git pull origin main 2>&1
        $pullResult | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

        if ($LASTEXITCODE -eq 0) {
            $newCommit = Get-ShortCommitHash $script:ConfigDir
            Write-Host "  Updated to $newCommit" -ForegroundColor Green
        } else {
            Write-Host "  Pull failed (exit code $LASTEXITCODE)" -ForegroundColor Red
            return
        }
    }
    finally {
        Pop-Location
    }

    # Regenerate settings.json from template with resolved paths
    Write-Host ""
    Write-Host "  Regenerating settings.json from template..." -ForegroundColor DarkGray
    New-ClaudeSettings -Force

    # Regenerate ways corpus so semantic matching is current after update
    $waysBin = Join-Path $script:ConfigDir "bin\ways.exe"
    if (-not (Test-Path $waysBin)) {
        $waysBin = Join-Path $script:ConfigDir "bin\ways"
    }
    if (Test-Path $waysBin) {
        Write-Host "  Regenerating ways corpus..." -ForegroundColor DarkGray
        # ways binary uses HOME to locate way files and cache dir.
        # Set HOME so it works correctly when invoked from PowerShell.
        $savedHome = $env:HOME
        $env:HOME = $env:USERPROFILE
        Push-Location $script:ConfigDir
        try {
            & $waysBin corpus
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Ways corpus ready." -ForegroundColor Green
            } else {
                Write-Host "  Ways corpus generation failed (exit $LASTEXITCODE)." -ForegroundColor Red
                Write-Host "  Semantic matching will be inactive until resolved." -ForegroundColor Yellow
            }
        } finally {
            Pop-Location
            $env:HOME = $savedHome
        }
    } else {
        Write-Host "  Ways binary not found." -ForegroundColor Yellow
        Write-Host "  Run: bash tools/ways-cli/download-ways.sh" -ForegroundColor DarkGray
    }

    Write-Host ""
}

function New-ClaudeSettings {
    <#
    .SYNOPSIS
        Generates settings.json from the Windows template with resolved paths

    .DESCRIPTION
        Reads settings.windows.json (the portable template) and generates
        settings.json with $env:USERPROFILE expanded to the actual path.

        Claude Code hooks are invoked by bash (Git Bash on Windows), which
        doesn't understand $env:USERPROFILE. This function resolves those
        to absolute paths so the hooks work correctly.

    .PARAMETER Force
        Overwrite existing settings.json without prompting

    .EXAMPLE
        New-ClaudeSettings
        Generates settings.json from template (prompts if exists)

    .EXAMPLE
        New-ClaudeSettings -Force
        Overwrites existing settings.json
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $templatePath = Join-Path $script:ConfigDir "settings.windows.json"
    $settingsPath = Join-Path $script:ConfigDir "settings.json"

    if (-not (Test-Path $templatePath)) {
        Write-Host "Template not found: $templatePath" -ForegroundColor Red
        Write-Host "Run Install-ClaudeConfig first to clone the config repo." -ForegroundColor Yellow
        return
    }

    if ((Test-Path $settingsPath) -and -not $Force) {
        Write-Host "settings.json already exists." -ForegroundColor Yellow
        Write-Host "Use -Force to overwrite, or edit it manually." -ForegroundColor DarkGray
        return
    }

    # Read template and resolve paths
    $content = Get-Content $templatePath -Raw

    # Replace $env:USERPROFILE with actual path using string replacement (not regex)
    # Forward slashes for bash compatibility
    $resolvedHome = $env:USERPROFILE -replace '\\', '/'

    # Replace $env:USERPROFILE\\ (JSON-escaped backslashes) with resolved path + /
    $content = $content.Replace('$env:USERPROFILE\\', "$resolvedHome/")
    # Replace any remaining bare $env:USERPROFILE references
    $content = $content.Replace('$env:USERPROFILE', $resolvedHome)

    # Normalize remaining JSON-escaped backslashes in paths to forward slashes
    # In JSON, \\ = literal \. After resolving $env:USERPROFILE, remaining \\
    # in .claude paths should become / for consistency
    $content = $content.Replace('.claude\\', '.claude/')
    $content = $content.Replace('hooks\\', 'hooks/')
    $content = $content.Replace('ways\\', 'ways/')
    $content = $content.Replace('win\\', 'win/')
    $content = $content.Replace('bin\\', 'bin/')

    Set-Content -Path $settingsPath -Value $content -Encoding UTF8

    Write-Host "Generated settings.json with resolved paths." -ForegroundColor Green
    Write-Host "  Template: $templatePath" -ForegroundColor DarkGray
    Write-Host "  Output:   $settingsPath" -ForegroundColor DarkGray
    Write-Host "  Home:     $resolvedHome" -ForegroundColor DarkGray
}

function Install-ClaudeConfig {
    <#
    .SYNOPSIS
        Bootstrap Claude Code configuration on a new device

    .DESCRIPTION
        Sets up ~/.claude/ by cloning your config repo. If the directory
        already exists, validates and fixes the git remote instead.
        Generates settings.json from the Windows template with resolved paths.

        Designed for first-time setup: install Claude Code, log in,
        then run this to apply your full configuration.

    .PARAMETER UseHttps
        Clone using HTTPS instead of SSH (useful if SSH keys aren't set up yet)

    .EXAMPLE
        Install-ClaudeConfig
        Clones config via SSH to ~/.claude/

    .EXAMPLE
        Install-ClaudeConfig -UseHttps
        Clones config via HTTPS to ~/.claude/
    #>
    [CmdletBinding()]
    param(
        [switch]$UseHttps
    )

    $cloneUrl = if ($UseHttps) { $script:RepoHttpsUrl } else { $script:RepoUrl }

    Write-Host ""
    Write-Host "Claude Code Config Bootstrap" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-Path $script:ConfigDir)) {
        # Fresh install — clone the repo
        Write-Host "Cloning config to $script:ConfigDir..." -ForegroundColor Cyan
        Write-Host "  From: $cloneUrl" -ForegroundColor DarkGray

        $result = git clone $cloneUrl $script:ConfigDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Clone failed:" -ForegroundColor Red
            $result | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }

            if (-not $UseHttps) {
                Write-Host ""
                Write-Host "  Tip: If SSH isn't configured, try:" -ForegroundColor Yellow
                Write-Host "    Install-ClaudeConfig -UseHttps" -ForegroundColor Yellow
            }
            return
        }

        Write-Host "  Cloned successfully!" -ForegroundColor Green

    } elseif (-not (Test-IsGitRepo $script:ConfigDir)) {
        # Directory exists but isn't a git repo
        # Back up existing content, then clone
        $backupDir = "$script:ConfigDir.backup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Host "Config directory exists but is not a git repo." -ForegroundColor Yellow
        Write-Host "  Backing up to: $backupDir" -ForegroundColor DarkGray
        Move-Item $script:ConfigDir $backupDir

        Write-Host "  Cloning config..." -ForegroundColor Cyan
        $result = git clone $cloneUrl $script:ConfigDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  Clone failed, restoring backup..." -ForegroundColor Red
            Move-Item $backupDir $script:ConfigDir
            return
        }

        # Restore credentials and runtime files from backup
        $restoreFiles = @(".credentials.json", "history.jsonl")
        foreach ($f in $restoreFiles) {
            $src = Join-Path $backupDir $f
            $dst = Join-Path $script:ConfigDir $f
            if ((Test-Path $src) -and -not (Test-Path $dst)) {
                Copy-Item $src $dst
                Write-Host "  Restored: $f" -ForegroundColor DarkGray
            }
        }

        Write-Host "  Cloned successfully! Backup at: $backupDir" -ForegroundColor Green

    } else {
        # Already a git repo — validate/fix remote
        Write-Host "Config directory exists and is a git repo." -ForegroundColor Green
        $currentRemote = Get-ConfigRemoteUrl

        $isCorrect = ($currentRemote -eq $script:RepoUrl) -or
                     ($currentRemote -eq $script:RepoHttpsUrl)

        if (-not $isCorrect) {
            Write-Host "  Remote URL: $currentRemote" -ForegroundColor Yellow
            Write-Host "  Expected:   $cloneUrl" -ForegroundColor DarkGray
            Write-Host "  Updating remote..." -ForegroundColor Cyan

            Push-Location $script:ConfigDir
            try {
                git remote set-url origin $cloneUrl 2>&1 | Out-Null
                Write-Host "  Remote updated to: $cloneUrl" -ForegroundColor Green
            } finally {
                Pop-Location
            }
        } else {
            Write-Host "  Remote OK: $currentRemote" -ForegroundColor Green
        }

        # Pull latest
        Write-Host "  Pulling latest..." -ForegroundColor DarkGray
        Push-Location $script:ConfigDir
        try {
            git pull origin main 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        } finally {
            Pop-Location
        }
    }

    # Generate settings.json from template
    Write-Host ""
    New-ClaudeSettings -Force

    # Verify setup
    Write-Host ""
    Write-Host "Verification:" -ForegroundColor White
    $checks = @(
        @{ Name = "settings.json"; OK = Test-Path (Join-Path $script:ConfigDir "settings.json") }
        @{ Name = "CLAUDE.md";     OK = Test-Path (Join-Path $script:ConfigDir "CLAUDE.md") }
        @{ Name = "hooks/";        OK = Test-Path (Join-Path $script:ConfigDir "hooks") }
        @{ Name = "agents/";       OK = Test-Path (Join-Path $script:ConfigDir "agents") }
    )
    foreach ($c in $checks) {
        $icon = if ($c.OK) { "[OK]" } else { "[!!]" }
        $color = if ($c.OK) { "Green" } else { "Yellow" }
        Write-Host "  $icon $($c.Name)" -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "Done! Config is ready at $script:ConfigDir" -ForegroundColor Green
    Write-Host ""
}

function Show-ClaudeConfigStatusOnStartup {
    <#
    .SYNOPSIS
        Lightweight startup check — only shows output if action needed

    .DESCRIPTION
        Called from PowerShell profile. Checks if config is behind upstream
        (cached, max once per hour). Silent when everything is fine.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:ConfigDir)) {
        Write-Host ""
        Write-Host "  Claude Config: " -NoNewline -ForegroundColor DarkGray
        Write-Host "Not found. Run Install-ClaudeConfig to set up." -ForegroundColor Yellow
        Write-Host ""
        return
    }

    if (-not (Test-IsGitRepo $script:ConfigDir)) {
        return
    }

    # Check if behind upstream (cached, max once per hour)
    $cacheFile = Join-Path $env:TEMP ".claude-config-status-cache"
    $cacheDuration = [TimeSpan]::FromHours(1)
    $needsCheck = $true
    $behind = 0

    if (Test-Path $cacheFile) {
        $cacheAge = (Get-Date) - (Get-Item $cacheFile).LastWriteTime
        if ($cacheAge -lt $cacheDuration) {
            $behind = [int](Get-Content $cacheFile -First 1 -ErrorAction SilentlyContinue)
            $needsCheck = $false
        }
    }

    if ($needsCheck) {
        Push-Location $script:ConfigDir
        try {
            git fetch origin main 2>$null | Out-Null
            $behind = [int](git rev-list HEAD..origin/main --count 2>$null)
            $behind | Out-File $cacheFile -NoNewline
        }
        catch {
            $behind = 0
        }
        finally {
            Pop-Location
        }
    }

    # Also check remote URL
    $remoteOk = $true
    $currentRemote = Get-ConfigRemoteUrl
    if ($currentRemote -and ($currentRemote -ne $script:RepoUrl) -and ($currentRemote -ne $script:RepoHttpsUrl)) {
        $remoteOk = $false
    }

    # Only show output if something needs attention
    if ($behind -gt 0 -or -not $remoteOk) {
        Write-Host ""
        Write-Host "  Claude Config: " -NoNewline -ForegroundColor DarkGray

        $messages = @()
        if ($behind -gt 0) { $messages += "$behind update(s) available" }
        if (-not $remoteOk) { $messages += "remote URL needs fix" }

        Write-Host ($messages -join ", ") -ForegroundColor Yellow
        Write-Host "  Run: " -NoNewline -ForegroundColor DarkGray
        Write-Host "ccstatus" -ForegroundColor Cyan -NoNewline
        Write-Host " for details" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# ============================================================================
# Aliases
# ============================================================================

Set-Alias -Name ccstatus -Value Get-ClaudeConfigStatus
Set-Alias -Name ccupdate -Value Update-ClaudeConfig
Set-Alias -Name ccinstall -Value Install-ClaudeConfig

# ============================================================================
# Export
# ============================================================================

Export-ModuleMember -Function @(
    'Get-ClaudeConfigStatus'
    'Update-ClaudeConfig'
    'Install-ClaudeConfig'
    'New-ClaudeSettings'
    'Show-ClaudeConfigStatusOnStartup'
) -Alias @(
    'ccstatus'
    'ccupdate'
    'ccinstall'
)
