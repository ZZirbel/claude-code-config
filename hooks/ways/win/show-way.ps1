# Show a "way" once per session (strips frontmatter, runs macro if configured)
# Usage: .\show-way.ps1 -Way "softwaredev/delivery/github" -SessionId "abc123" -Trigger "prompt"
#
# Way paths can be nested: "softwaredev/delivery/github", "awsops/iam", etc.
# Looks for: {way-path}/way.md and optionally {way-path}/macro.ps1
#
# STATE MACHINE:
# | Marker State | Action                    |
# |--------------|---------------------------|
# | not exists   | output way, create marker |
# | exists       | no-op (idempotent)        |
#
# MACRO SUPPORT:
# If frontmatter contains `macro: prepend` or `macro: append`,
# runs {way-path}/macro.ps1 and combines output with static content.

param(
    [Parameter(Mandatory=$true)]
    [string]$Way,

    [string]$SessionId,

    [string]$Trigger = "unknown"
)

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $PWD.Path }
$waysDir = Join-Path $env:USERPROFILE ".claude\hooks\ways"
$winDir = Join-Path $waysDir "win"

# Load match-way for helper functions
. (Join-Path $winDir "match-way.ps1")
. (Join-Path $winDir "detect-scope.ps1")

$scope = Get-Scope $SessionId
$team = Get-Team $SessionId

# Check if domain is disabled via ~/.claude/ways.json
$waysConfig = Join-Path $env:USERPROFILE ".claude\ways.json"
$domain = ($Way -split "/")[0]

if (Test-Path $waysConfig) {
    try {
        $config = Get-Content $waysConfig -Raw | ConvertFrom-Json
        if ($config.disabled -contains $domain) {
            exit 0
        }
    } catch {}
}

# Sanitize way path for marker filename (replace / with -)
$wayMarkerName = $Way -replace "/", "-"

# Project-local takes precedence over global
$wayFile = $null
$wayDir = $null
$isProjectLocal = $false

$projectWayFile = Join-Path $projectDir ".claude\ways\$Way\way.md"
$globalWayFile = Join-Path $waysDir "$Way\way.md"

if (Test-Path $projectWayFile) {
    $wayFile = $projectWayFile
    $wayDir = Split-Path $wayFile -Parent
    $isProjectLocal = $true
} elseif (Test-Path $globalWayFile) {
    $wayFile = $globalWayFile
    $wayDir = Split-Path $wayFile -Parent
} else {
    exit 0
}

# Check if project is trusted for macro execution
function Test-ProjectTrusted {
    $trustFile = Join-Path $env:USERPROFILE ".claude\trusted-project-macros"
    if (Test-Path $trustFile) {
        return (Get-Content $trustFile) -contains $projectDir
    }
    return $false
}

# Marker: scoped to session_id
$markerDate = if ($SessionId) { $SessionId } else { Get-Date -Format "yyyyMMdd" }
$marker = Join-Path $env:TEMP ".claude-way-$wayMarkerName-$markerDate"

if (-not (Test-Path $marker)) {
    $content = Get-Content $wayFile -Raw

    # Extract macro field from frontmatter
    $macroPos = Get-FrontmatterField -Content $content -FieldName "macro"

    # Check for macro script (same directory as way file)
    $macroFile = Join-Path $wayDir "macro.ps1"
    $macroOut = ""

    if ($macroPos -and (Test-Path $macroFile)) {
        # SECURITY: Skip project-local macros unless project is explicitly trusted
        if ($isProjectLocal -and -not (Test-ProjectTrusted)) {
            Write-Output "**Note**: Project-local macro skipped (add $projectDir to ~/.claude/trusted-project-macros to enable)"
        } else {
            try {
                $macroOut = & $macroFile 2>$null
            } catch {}
        }
    }

    # Output based on macro position
    if ($macroPos -eq "prepend" -and $macroOut) {
        Write-Output $macroOut
        Write-Output ""
    }

    # Output static content, stripping YAML frontmatter
    Write-Output (Remove-Frontmatter -Content $content)

    if ($macroPos -eq "append" -and $macroOut) {
        Write-Output ""
        Write-Output $macroOut
    }

    # Create marker
    "" | Set-Content $marker -NoNewline

    # Log event
    $logScript = Join-Path $winDir "log-event.ps1"
    if (Test-Path $logScript) {
        $logArgs = @("event=way_fired", "way=$Way", "domain=$domain", "trigger=$Trigger", "scope=$scope", "project=$projectDir", "session=$SessionId")
        if ($team) { $logArgs += "team=$team" }
        & $logScript @logArgs
    }
}
