#Requires -Version 5.1
# PreToolUse: Check file operations against ways - thin dispatcher
#
# The ways binary handles: file pattern matching, check scoring,
# session state, and content output.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\require-ways.ps1"

$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $fp = $data.tool_input.file_path
    $sessionId = $data.session_id
    $agentId = $data.agent_id
    $cwd = $data.cwd
} catch {
    exit 0
}

if ([string]::IsNullOrEmpty($fp)) { exit 0 }

if (-not [string]::IsNullOrEmpty($agentId)) {
    $env:CLAUDE_AGENT_ID = $agentId
}

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }
$env:CLAUDE_PROJECT_DIR = $projectDir

& $script:WAYS_BIN scan file `
    --path "$fp" `
    --session "$sessionId" `
    --project "$projectDir"
