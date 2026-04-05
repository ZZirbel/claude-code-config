#Requires -Version 5.1
# Stop hook: Analyze Claude's response for topic awareness
#
# Reads the transcript after Claude responds, extracts topics,
# and writes state for the next UserPromptSubmit to use.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
    $agentId = $data.agent_id
    $transcript = $data.transcript_path
    $stopActive = $data.stop_hook_active
} catch {
    exit 0
}

if (-not [string]::IsNullOrEmpty($agentId)) {
    $env:CLAUDE_AGENT_ID = $agentId
}

# Prevent infinite loops
if ($stopActive -eq $true -or $stopActive -eq "true") { exit 0 }

# Need transcript
if ([string]::IsNullOrEmpty($transcript) -or -not (Test-Path $transcript)) { exit 0 }

$stateFile = Join-Path $env:TEMP "claude-response-topics-$sessionId"

# Extract last assistant message from transcript (JSONL format)
$lastLines = Get-Content $transcript -Tail 100 -ErrorAction SilentlyContinue
$lastResponse = ""
foreach ($line in $lastLines) {
    if ($line -match '"type":"assistant"' -or $line -match '"type": "assistant"') {
        try {
            $msg = $line | ConvertFrom-Json
            foreach ($content in $msg.message.content) {
                if ($content.text) {
                    $lastResponse = $content.text
                }
            }
        } catch {}
    }
}

if ([string]::IsNullOrEmpty($lastResponse)) { exit 0 }

# Truncate to 2000 chars
if ($lastResponse.Length -gt 2000) {
    $lastResponse = $lastResponse.Substring(0, 2000)
}

# Extract potential topics (simple keyword extraction)
$topicKeywords = @(
    'api', 'test', 'debug', 'config', 'security', 'auth', 'database',
    'migration', 'deploy', 'git', 'commit', 'pr', 'issue', 'error',
    'hook', 'trigger', 'way', 'todo', 'context', 'token', 'model', 'prompt'
)

$lowerResponse = $lastResponse.ToLower()
$foundTopics = @()
foreach ($keyword in $topicKeywords) {
    if ($lowerResponse -match "\b$keyword\b") {
        $foundTopics += $keyword
    }
}

$topics = ($foundTopics | Select-Object -Unique | Select-Object -First 10) -join ' '

# Write state for next turn
if (-not [string]::IsNullOrEmpty($topics)) {
    $state = @{
        timestamp       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        topics          = $topics
        response_length = $lastResponse.Length
    } | ConvertTo-Json -Compress

    Set-Content -Path $stateFile -Value $state -Force -ErrorAction SilentlyContinue
}
