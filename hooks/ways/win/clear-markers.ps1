#Requires -Version 5.1
# Clear way markers for fresh session
# Called on SessionStart and after compaction
#
# Reads session_id from stdin JSON input (Claude Code hook format)
# Clears this session's state directory only - other sessions stay intact

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\sessions-root.ps1"

$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
} catch {
    $sessionId = ""
}

# Clear session state
if (-not [string]::IsNullOrEmpty($sessionId)) {
    $sessionDir = Join-Path $script:SESSIONS_ROOT $sessionId
    Remove-Item $sessionDir -Recurse -Force -ErrorAction SilentlyContinue
} else {
    # No session ID - legacy fallback, clear everything
    Remove-Item $script:SESSIONS_ROOT -Recurse -Force -ErrorAction SilentlyContinue
}

# Log session event
$statsDir = Join-Path $env:USERPROFILE ".claude\stats"
New-Item $statsDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $PWD.Path }
$session = if (-not [string]::IsNullOrEmpty($sessionId)) { $sessionId } else { "unknown" }

$logEntry = @{
    ts      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    event   = "session_start"
    project = $projectDir
    session = $session
} | ConvertTo-Json -Compress

Add-Content -Path (Join-Path $statsDir "events.jsonl") -Value $logEntry -ErrorAction SilentlyContinue
