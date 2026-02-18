# Log a ways event to ~/.claude/stats/events.jsonl
# Usage: .\log-event.ps1 -Event "way_fired" -Way "softwaredev/delivery/github" -Trigger "prompt"
#
# All values are safely JSON-encoded. Event log is append-only JSONL.

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$KeyValuePairs
)

$statsDir = Join-Path $env:USERPROFILE ".claude\stats"
if (-not (Test-Path $statsDir)) {
    New-Item -ItemType Directory -Path $statsDir -Force | Out-Null
}

$eventFile = Join-Path $statsDir "events.jsonl"

# Build event object
$event = @{
    ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

# Parse key=value pairs
foreach ($kv in $KeyValuePairs) {
    if ($kv -match '^([^=]+)=(.*)$') {
        $event[$Matches[1]] = $Matches[2]
    }
}

# Append to JSONL file
$json = $event | ConvertTo-Json -Compress
Add-Content -Path $eventFile -Value $json -Encoding UTF8
