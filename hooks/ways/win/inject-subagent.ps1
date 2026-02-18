# SubagentStart - Inject subagent-scoped ways from stash
#
# TRIGGER FLOW:
# SubagentStart -> read stash file -> emit way content (bypass markers)
#
# Phase 2 of two-phase subagent injection:
# 1. PreToolUse:Task (check-task-pre.ps1) stashed matched way paths
# 2. This script reads the stash, emits way content as additionalContext

param()

# Read JSON from stdin
$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
    $cwd = $data.cwd
} catch {
    exit 0
}

if (-not $sessionId) { exit 0 }

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }
$waysDir = Join-Path $env:USERPROFILE ".claude\hooks\ways"
$winDir = Join-Path $waysDir "win"

$stashDir = Join-Path $env:TEMP ".claude-subagent-stash-$sessionId"
if (-not (Test-Path $stashDir)) { exit 0 }

# Load match-way for helper functions
. (Join-Path $winDir "match-way.ps1")

# Claim the oldest stash file (FIFO for parallel Task invocations)
$stashFiles = Get-ChildItem -Path $stashDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name
if ($stashFiles.Count -eq 0) { exit 0 }

$oldest = $stashFiles[0]
$claimed = $oldest.FullName + ".claimed"

try {
    Move-Item -Path $oldest.FullName -Destination $claimed -Force -ErrorAction Stop
} catch {
    exit 0
}

# Read stash data
try {
    $stashData = Get-Content $claimed -Raw | ConvertFrom-Json
    $ways = $stashData.ways
    $isTeammate = $stashData.is_teammate
    $teamName = $stashData.team_name
} catch {
    Remove-Item $claimed -Force -ErrorAction SilentlyContinue
    exit 0
}

Remove-Item $claimed -Force -ErrorAction SilentlyContinue

# If this is a teammate spawn, write a marker
if ($isTeammate) {
    $teammateMarker = Join-Path $env:TEMP ".claude-teammate-$sessionId"
    Set-Content -Path $teammateMarker -Value $teamName -NoNewline
}

if (-not $ways -or $ways.Count -eq 0) { exit 0 }

$context = ""

foreach ($wayPath in $ways) {
    if (-not $wayPath) { continue }

    # Resolve way file (project-local > global)
    $wayFile = $null
    $wayDir = $null

    $projectWayFile = Join-Path $projectDir ".claude\ways\$wayPath\way.md"
    $globalWayFile = Join-Path $waysDir "$wayPath\way.md"

    if (Test-Path $projectWayFile) {
        $wayFile = $projectWayFile
        $wayDir = Split-Path $wayFile -Parent
    } elseif (Test-Path $globalWayFile) {
        $wayFile = $globalWayFile
        $wayDir = Split-Path $wayFile -Parent
    }

    if (-not $wayFile) { continue }

    # Check domain disabled
    $domain = ($wayPath -split "/")[0]
    $waysConfig = Join-Path $env:USERPROFILE ".claude\ways.json"
    if (Test-Path $waysConfig) {
        try {
            $config = Get-Content $waysConfig -Raw | ConvertFrom-Json
            if ($config.disabled -contains $domain) { continue }
        } catch {}
    }

    $content = Get-Content $wayFile -Raw

    # Extract macro position
    $macroPos = Get-FrontmatterField -Content $content -FieldName "macro"
    $macroFile = Join-Path $wayDir "macro.ps1"
    $macroOut = ""

    if ($macroPos -and (Test-Path $macroFile)) {
        # Only run global macros or trusted project macros
        if ($wayFile -like "$waysDir*") {
            try { $macroOut = & $macroFile 2>$null } catch {}
        } else {
            $trustFile = Join-Path $env:USERPROFILE ".claude\trusted-project-macros"
            if ((Test-Path $trustFile) -and ((Get-Content $trustFile) -contains $projectDir)) {
                try { $macroOut = & $macroFile 2>$null } catch {}
            }
        }
    }

    # Build way output
    $wayContent = ""
    if ($macroPos -eq "prepend" -and $macroOut) {
        $wayContent += $macroOut + "`n"
    }

    $wayContent += Remove-Frontmatter -Content $content

    if ($macroPos -eq "append" -and $macroOut) {
        $wayContent += "`n" + $macroOut
    }

    if ($wayContent) {
        $context += $wayContent + "`n`n"

        # Log event
        $logScript = Join-Path $winDir "log-event.ps1"
        $scope = if ($isTeammate) { "teammate" } else { "subagent" }
        if (Test-Path $logScript) {
            $logArgs = @("event=way_fired", "way=$wayPath", "domain=$domain", "trigger=$scope", "scope=$scope", "project=$projectDir", "session=$sessionId")
            if ($teamName) { $logArgs += "team=$teamName" }
            & $logScript @logArgs
        }
    }
}

# Output JSON for SubagentStart
if ($context.Trim()) {
    $trimmed = $context.TrimEnd("`n")
    if ($trimmed.Trim()) {
        $result = @{
            hookSpecificOutput = @{
                hookEventName = "SubagentStart"
                additionalContext = $trimmed
            }
        } | ConvertTo-Json -Compress -Depth 3
        Write-Output $result
    }
}
