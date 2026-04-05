#Requires -Version 5.1
# PreToolUse:Task - thin dispatcher to ways binary
#
# Phase 1 of two-phase subagent injection:
# 1. This script: ways scan task (matches ways, writes stash)
# 2. SubagentStart: inject-subagent.ps1 (reads stash, emits content)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\require-ways.ps1"

$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $taskPrompt = ($data.tool_input.prompt).ToLower()
    $sessionId = $data.session_id
    $agentId = $data.agent_id
    $cwd = $data.cwd
    $teamName = $data.tool_input.team_name
} catch {
    exit 0
}

if ([string]::IsNullOrEmpty($taskPrompt) -or [string]::IsNullOrEmpty($sessionId)) { exit 0 }

if (-not [string]::IsNullOrEmpty($agentId)) {
    $env:CLAUDE_AGENT_ID = $agentId
}

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }

$args_ = @("scan", "task", "--query", $taskPrompt, "--session", $sessionId, "--project", $projectDir)
if (-not [string]::IsNullOrEmpty($teamName)) {
    $args_ += @("--team", $teamName)
}

& $script:WAYS_BIN @args_

# Never block Task creation
exit 0
