# PreToolUse:Task - Stash subagent-scoped ways for SubagentStart
#
# TRIGGER FLOW:
# PreToolUse:Task -> scan_ways() -> write stash for injection
#
# Phase 1 of two-phase subagent injection:
# 1. PreToolUse:Task scans Task prompt against ways with subagent scope
# 2. SubagentStart (inject-subagent.ps1) reads stash and emits content

param()

# Read JSON from stdin
$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $taskPrompt = ($data.tool_input.prompt).ToLower()
    $sessionId = $data.session_id
    $cwd = $data.cwd
    $teamName = $data.tool_input.team_name
} catch {
    exit 0
}

if (-not $taskPrompt -or -not $sessionId) { exit 0 }

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }
$waysDir = Join-Path $env:USERPROFILE ".claude\hooks\ways"
$winDir = Join-Path $waysDir "win"

# Load shared modules
. (Join-Path $winDir "match-way.ps1")

Initialize-SemanticEngine

$isTeammate = [bool]$teamName
$matchedWays = @()

$stashDir = Join-Path $env:TEMP ".claude-subagent-stash-$sessionId"
if (-not (Test-Path $stashDir)) {
    New-Item -ItemType Directory -Path $stashDir -Force | Out-Null
}

function Scan-WaysForSubagent {
    param([string]$Dir)

    if (-not (Test-Path $Dir)) { return }

    $wayFiles = Get-ChildItem -Path $Dir -Filter "way.md" -Recurse -File -ErrorAction SilentlyContinue

    foreach ($wayFile in $wayFiles) {
        $wayPath = $wayFile.FullName.Substring($Dir.Length + 1)
        $wayPath = $wayPath -replace "\\way\.md$", ""
        $wayPath = $wayPath -replace "\\", "/"

        $content = Get-Content $wayFile.FullName -Raw

        # Must have subagent or teammate scope
        $scope = Get-FrontmatterField -Content $content -FieldName "scope"
        if (-not $scope) { $scope = "agent" }

        if ($isTeammate) {
            if ($scope -notmatch "\b(subagent|teammate)\b") { continue }
        } else {
            if ($scope -notmatch "\bsubagent\b") { continue }
        }

        # Skip state-triggered ways
        $trigger = Get-FrontmatterField -Content $content -FieldName "trigger"
        if ($trigger) { continue }

        # Extract matching fields
        $pattern = Get-FrontmatterField -Content $content -FieldName "pattern"
        $description = Get-FrontmatterField -Content $content -FieldName "description"
        $vocabulary = Get-FrontmatterField -Content $content -FieldName "vocabulary"
        $threshold = Get-FrontmatterField -Content $content -FieldName "threshold"

        $thresholdVal = 2.0
        if ($threshold) {
            try { $thresholdVal = [double]$threshold } catch {}
        }

        if (Test-WayMatch -Prompt $taskPrompt -Pattern $pattern -Description $description -Vocabulary $vocabulary -Threshold $thresholdVal) {
            $script:matchedWays += $wayPath
        }
    }
}

# Scan project-local first, then global
$projectWays = Join-Path $projectDir ".claude\ways"
Scan-WaysForSubagent -Dir $projectWays
Scan-WaysForSubagent -Dir $waysDir

# Write stash if any ways matched
if ($matchedWays.Count -gt 0) {
    $timestamp = [long](Get-Date -UFormat %s) * 1000000000 + (Get-Random -Maximum 999999999)
    $stashFile = Join-Path $stashDir "$timestamp.json"

    $stashData = @{
        ways = $matchedWays
        is_teammate = $isTeammate
        team_name = if ($teamName) { $teamName } else { "" }
    }

    $stashData | ConvertTo-Json -Compress | Set-Content $stashFile -Encoding UTF8
}

# Never block Task creation
exit 0
