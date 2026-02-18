# Detect current execution scope: agent, teammate, or subagent
# Usage: . $PSScriptRoot\detect-scope.ps1
#        $scope = Get-Scope $sessionId
#
# Detection: checks for teammate marker created by inject-subagent.ps1
# Marker: $env:TEMP\.claude-teammate-{session_id}

function Get-Scope {
    param([string]$SessionId)

    $marker = Join-Path $env:TEMP ".claude-teammate-$SessionId"
    if (Test-Path $marker) {
        return "teammate"
    }
    return "agent"
}

function Get-Team {
    param([string]$SessionId)

    $marker = Join-Path $env:TEMP ".claude-teammate-$SessionId"
    if (Test-Path $marker) {
        return (Get-Content $marker -Raw).Trim()
    }
    return ""
}

# Check if a way's scope field matches the current execution scope
function Test-ScopeMatch {
    param(
        [string]$ScopeField = "agent",
        [string]$CurrentScope
    )

    return $ScopeField -match "\b$CurrentScope\b"
}
