#Requires -Version 5.1
# PreToolUse: Check bash commands against ways - thin dispatcher
#
# The ways binary handles: command pattern matching, semantic scoring,
# check curve scoring, session state, and content output.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\require-ways.ps1"

$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $cmd = $data.tool_input.command
    $desc = ($data.tool_input.description).ToLower()
    $sessionId = $data.session_id
    $agentId = $data.agent_id
    $cwd = $data.cwd
} catch {
    exit 0
}

if (-not [string]::IsNullOrEmpty($agentId)) {
    $env:CLAUDE_AGENT_ID = $agentId
}

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }
$env:CLAUDE_PROJECT_DIR = $projectDir

& $script:WAYS_BIN scan command `
    --command "$cmd" `
    --description "$desc" `
    --session "$sessionId" `
    --project "$projectDir"
