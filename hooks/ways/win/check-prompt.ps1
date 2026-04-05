#Requires -Version 5.1
# Check user prompts against ways - thin dispatcher to ways binary
#
# The ways binary handles: file walking, frontmatter extraction, pattern
# + semantic matching, scope/precondition gating, parent threshold
# lowering, session markers, macro dispatch, and content output.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\require-ways.ps1"

$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $prompt = ($data.prompt).ToLower()
    $sessionId = $data.session_id
    $cwd = $data.cwd
    $agentId = $data.agent_id
} catch {
    exit 0
}

if (-not [string]::IsNullOrEmpty($agentId)) {
    $env:CLAUDE_AGENT_ID = $agentId
}

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }

# Read response topics from Stop hook (if available)
$responseState = Join-Path $env:TEMP "claude-response-topics-$sessionId"
$responseTopics = ""
if (Test-Path $responseState) {
    try {
        $stateData = Get-Content $responseState -Raw | ConvertFrom-Json
        $responseTopics = $stateData.topics
    } catch {}
}

# Combined context: user prompt + Claude's recent topics
$combined = "$prompt $responseTopics"

$env:CLAUDE_PROJECT_DIR = $projectDir
& $script:WAYS_BIN scan prompt `
    --query "$combined" `
    --session "$sessionId" `
    --project "$projectDir"
