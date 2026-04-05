#Requires -Version 5.1
# State-based trigger evaluator - thin dispatcher to ways binary
#
# Evaluates: context-threshold, file-exists, session-start triggers.
# Also handles core guidance re-injection safety net.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\require-ways.ps1"

$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
    $agentId = $data.agent_id
    $transcript = $data.transcript_path
    $cwd = $data.cwd
} catch {
    exit 0
}

if (-not [string]::IsNullOrEmpty($agentId)) {
    $env:CLAUDE_AGENT_ID = $agentId
}

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }
$env:CLAUDE_PROJECT_DIR = $projectDir

$args_ = @("scan", "state", "--session", $sessionId, "--project", $projectDir)
if (-not [string]::IsNullOrEmpty($transcript)) {
    $args_ += @("--transcript", $transcript)
}

& $script:WAYS_BIN @args_
