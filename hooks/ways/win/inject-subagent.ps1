#Requires -Version 5.1
# SubagentStart - Inject subagent-scoped ways from stash
#
# TRIGGER FLOW:
# SubagentStart -> read stash file -> emit way content (bypass markers)
#
# Phase 2 of two-phase subagent injection:
# 1. PreToolUse:Task (check-task-pre.ps1) stashed matched way paths
# 2. This script reads the stash, emits way content as additionalContext

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\sessions-root.ps1"

$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
    $agentId = $data.agent_id
    $cwd = $data.cwd
} catch {
    exit 0
}

if ([string]::IsNullOrEmpty($sessionId)) { exit 0 }

if (-not [string]::IsNullOrEmpty($agentId)) {
    $env:CLAUDE_AGENT_ID = $agentId
}

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }

$stashDir = Join-Path $script:SESSIONS_ROOT "$sessionId\subagent-stash"
if (-not (Test-Path $stashDir -PathType Container)) { exit 0 }

# Claim the oldest stash file (FIFO for parallel Task invocations)
$oldest = Get-ChildItem -Path $stashDir -Filter "*.json" -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -First 1
if (-not $oldest) { exit 0 }

# Atomic claim: rename so no other SubagentStart grabs it
$claimed = "$($oldest.FullName).claimed"
try {
    Move-Item $oldest.FullName $claimed -Force -ErrorAction Stop
} catch {
    exit 0
}

# Read matched way paths, channels, teammate flag, and team name
try {
    $stashData = Get-Content $claimed -Raw | ConvertFrom-Json
    $ways = $stashData.ways
    $channels = $stashData.channels
    $isTeammate = $stashData.is_teammate
    $teamName = $stashData.team_name
} catch {
    Remove-Item $claimed -Force -ErrorAction SilentlyContinue
    exit 0
}
Remove-Item $claimed -Force -ErrorAction SilentlyContinue

# If this is a teammate spawn, write a marker
if ($isTeammate -eq $true -or $isTeammate -eq "true") {
    $sessionDir = Join-Path $script:SESSIONS_ROOT $sessionId
    New-Item $sessionDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    Set-Content -Path (Join-Path $sessionDir "teammate") -Value $teamName -Force -ErrorAction SilentlyContinue
}

if (-not $ways -or $ways.Count -eq 0) { exit 0 }

# Emit way content for each matched way (bypassing markers)
$context = ""
$wayIdx = 0

foreach ($waypath in $ways) {
    if ([string]::IsNullOrEmpty($waypath)) { continue }

    $matchCh = if ($channels -and $wayIdx -lt $channels.Count) { $channels[$wayIdx] } else { "prompt" }
    $wayIdx++

    # Resolve way file (project-local > global)
    $wayFile = $null
    $wayDir = $null

    foreach ($base in @("$projectDir\.claude\ways", "$env:USERPROFILE\.claude\hooks\ways")) {
        $candidate = Join-Path $base $waypath
        if (-not (Test-Path $candidate -PathType Container)) { continue }

        foreach ($f in (Get-ChildItem -Path $candidate -Filter "*.md" -File -ErrorAction SilentlyContinue)) {
            if ($f.Name -match '\.check\.md$') { continue }
            $firstLine = Get-Content $f.FullName -TotalCount 1 -ErrorAction SilentlyContinue
            if ($firstLine -eq '---') {
                $wayFile = $f.FullName
                $wayDir = $candidate
                break
            }
        }
        if ($wayFile) { break }
    }
    if (-not $wayFile) { continue }

    # Check domain disabled
    $domain = ($waypath -split '[/\\]')[0]
    $waysConfig = Join-Path $env:USERPROFILE ".claude\ways.json"
    if (Test-Path $waysConfig) {
        try {
            $config = Get-Content $waysConfig -Raw | ConvertFrom-Json
            if ($config.disabled -and $config.disabled -contains $domain) { continue }
        } catch {}
    }

    # Extract macro position from frontmatter
    $wayContent = Get-Content $wayFile -Raw
    $macroPos = $null
    if ($wayContent -match '(?ms)^---\r?\n(.+?)\r?\n---') {
        $fm = $Matches[1]
        if ($fm -match '(?m)^macro:\s*(.+)$') {
            $macroPos = $Matches[1].Trim()
        }
    }

    $macroFile = Join-Path $wayDir "macro.sh"
    $macroOut = ""

    if ($macroPos -and (Test-Path $macroFile)) {
        # Only run global macros directly; project-local need trust check
        if ($wayFile -like "$env:USERPROFILE\.claude\hooks\ways\*") {
            $macroOut = bash $macroFile 2>$null
        } else {
            $trustFile = Join-Path $env:USERPROFILE ".claude\trusted-project-macros"
            if ((Test-Path $trustFile) -and ((Get-Content $trustFile) -contains $projectDir)) {
                $macroOut = bash $macroFile 2>$null
            }
        }
    }

    # Build way output - strip frontmatter
    $bodyContent = $wayContent -replace '(?ms)^---\r?\n.+?\r?\n---\r?\n', ''
    $wayOutput = ""

    if ($macroPos -eq "prepend" -and -not [string]::IsNullOrEmpty($macroOut)) {
        $wayOutput += $macroOut + "`n"
    }

    $wayOutput += $bodyContent

    if ($macroPos -eq "append" -and -not [string]::IsNullOrEmpty($macroOut)) {
        $wayOutput += "`n" + $macroOut
    }

    if (-not [string]::IsNullOrEmpty($wayOutput)) {
        $context += $wayOutput + "`n`n"

        # Log event
        $scope = if ($isTeammate -eq $true -or $isTeammate -eq "true") { "teammate" } else { "subagent" }
        $statsDir = Join-Path $env:USERPROFILE ".claude\stats"
        New-Item $statsDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        $logEntry = @{
            ts      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            event   = "way_fired"
            way     = $waypath
            domain  = $domain
            trigger = $matchCh
            scope   = $scope
            project = $projectDir
            session = $sessionId
        }
        if (-not [string]::IsNullOrEmpty($teamName)) {
            $logEntry.team = $teamName
        }
        $logJson = $logEntry | ConvertTo-Json -Compress
        Add-Content -Path (Join-Path $statsDir "events.jsonl") -Value $logJson -ErrorAction SilentlyContinue
    }
}

# Output JSON for SubagentStart (additionalContext format)
if (-not [string]::IsNullOrEmpty($context)) {
    $trimmed = $context.TrimEnd("`n")
    if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
        $output = @{
            hookSpecificOutput = @{
                hookEventName     = "SubagentStart"
                additionalContext = $trimmed
            }
        } | ConvertTo-Json -Compress
        Write-Output $output
    }
}
