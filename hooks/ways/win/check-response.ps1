# Stop hook: Analyze Claude's response for topic awareness
#
# Reads the transcript after Claude responds, extracts topics,
# and writes state for the next UserPromptSubmit to use.
#
# This enables ways to trigger based on what Claude discussed,
# not just what the user asked.

param()

# Read JSON from stdin
$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
    $transcriptPath = $data.transcript_path
    $stopActive = $data.stop_hook_active
} catch {
    exit 0
}

# Prevent infinite loops
if ($stopActive -eq $true) { exit 0 }

# Need transcript
if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) { exit 0 }

$stateFile = Join-Path $env:TEMP "claude-response-topics-$sessionId"

# Extract last assistant message from transcript (JSONL format)
try {
    $lines = Get-Content $transcriptPath -Tail 100 -ErrorAction SilentlyContinue
    $lastResponse = ""

    foreach ($line in ($lines | Where-Object { $_ -match '"type":"assistant"' })) {
        try {
            $msg = $line | ConvertFrom-Json
            foreach ($content in $msg.message.content) {
                if ($content.text) {
                    $lastResponse = $content.text
                }
            }
        } catch {}
    }

    if (-not $lastResponse) { exit 0 }

    # Limit to first 2000 chars
    if ($lastResponse.Length -gt 2000) {
        $lastResponse = $lastResponse.Substring(0, 2000)
    }
} catch {
    exit 0
}

# Extract potential topics (simple keyword extraction)
$keywords = @("api", "test", "debug", "config", "security", "auth", "database",
              "migration", "deploy", "git", "commit", "pr", "issue", "error",
              "hook", "trigger", "way", "todo", "context", "token", "model", "prompt")

$topics = @()
$words = $lastResponse.ToLower() -split '\W+' | Where-Object { $_ }

foreach ($keyword in $keywords) {
    if ($words -contains $keyword) {
        $topics += $keyword
    }
}

$topicsStr = ($topics | Select-Object -Unique | Select-Object -First 10) -join " "

# Write state for next turn
if ($topicsStr) {
    $state = @{
        timestamp = (Get-Date).ToString("o")
        topics = $topicsStr
        response_length = $lastResponse.Length
    }
    $state | ConvertTo-Json -Compress | Set-Content $stateFile -Encoding UTF8
}
