# PreToolUse hook for TaskCreate
# Sets marker so context-threshold nag stops repeating

param()

# Read JSON from stdin
$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
} catch {
    exit 0
}

if ($sessionId) {
    $marker = Join-Path $env:TEMP ".claude-tasks-active-$sessionId"
    "" | Set-Content $marker -NoNewline
}
