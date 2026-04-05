#Requires -Version 5.1
# PreToolUse hook for TaskCreate
# Sets marker so context-threshold nag stops repeating

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\sessions-root.ps1"

$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
    $agentId = $data.agent_id
} catch {
    exit 0
}

if (-not [string]::IsNullOrEmpty($agentId)) {
    $env:CLAUDE_AGENT_ID = $agentId
}

if (-not [string]::IsNullOrEmpty($sessionId)) {
    $sessionDir = Join-Path $script:SESSIONS_ROOT $sessionId
    New-Item $sessionDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item (Join-Path $sessionDir "tasks-active") -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
}
