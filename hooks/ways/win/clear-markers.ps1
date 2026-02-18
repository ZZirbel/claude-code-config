# Clear way markers for fresh session
# Called on SessionStart and after compaction
#
# Reads session_id from stdin JSON input (Claude Code hook format)
# Clears ALL markers so guidance can trigger fresh in the new session

param()

# Read JSON from stdin
$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
} catch {
    $sessionId = ""
}

# Clear all markers (session IDs change on restart anyway)
$tempPath = $env:TEMP

# Clear way markers
Get-ChildItem -Path $tempPath -Filter ".claude-way-*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# Clear core markers
Get-ChildItem -Path $tempPath -Filter ".claude-core-*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# Clear tasks-active markers
Get-ChildItem -Path $tempPath -Filter ".claude-tasks-active-*" -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

# Clear subagent stash directories
Get-ChildItem -Path $tempPath -Directory -Filter ".claude-subagent-stash-*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

# Log session event
$logScript = Join-Path $PSScriptRoot "log-event.ps1"
$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $PWD.Path }
$session = if ($sessionId) { $sessionId } else { "unknown" }

if (Test-Path $logScript) {
    & $logScript "event=session_start" "project=$projectDir" "session=$session"
}
