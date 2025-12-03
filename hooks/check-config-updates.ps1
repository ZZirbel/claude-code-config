# Check if claude-code-config has updates available
# Runs once per day to avoid spam

$TimestampFile = "$env:USERPROFILE\.claude\.last-plugin-update-check"
$CurrentTime = [int][double]::Parse((Get-Date -UFormat %s))
$OneDay = 86400

# Check if we've run this recently
if (Test-Path $TimestampFile) {
    $LastCheck = [int](Get-Content $TimestampFile -ErrorAction SilentlyContinue)
    $TimeDiff = $CurrentTime - $LastCheck

    if ($TimeDiff -lt $OneDay) {
        # Checked recently, skip
        exit 0
    }
}

# Update timestamp
$CurrentTime | Out-File -FilePath $TimestampFile -NoNewline

# Check if we're in a git repo with the config
$ClaudeDir = "$env:USERPROFILE\.claude"
if (-not (Test-Path "$ClaudeDir\.git")) {
    # Not a git repo, skip
    exit 0
}

# Check for gh CLI
$ghExists = Get-Command gh -ErrorAction SilentlyContinue
if (-not $ghExists) {
    # No gh CLI, can't check for updates
    exit 0
}

# Get current local commit
try {
    Push-Location $ClaudeDir
    $LocalCommit = git rev-parse HEAD 2>$null
    $RemoteCommit = git ls-remote origin HEAD 2>$null | ForEach-Object { $_.Split()[0] }
    Pop-Location
} catch {
    exit 0
}

if ([string]::IsNullOrEmpty($LocalCommit) -or [string]::IsNullOrEmpty($RemoteCommit)) {
    exit 0
}

# Compare commits
if ($LocalCommit -ne $RemoteCommit) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "UPDATE AVAILABLE: claude-code-config"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
    Write-Host "Your fork has updates available from upstream."
    Write-Host ""
    Write-Host "To update:"
    Write-Host "  cd $ClaudeDir"
    Write-Host "  git pull"
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
}
