# State-based way trigger evaluator
# Scans ways for trigger: declarations and evaluates conditions
#
# Supported triggers:
#   trigger: context-threshold
#   trigger: file-exists
#   trigger: session-start
#
# Runs every UserPromptSubmit, evaluates conditions, fires matching ways.

param()

# Read JSON from stdin
$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
    $transcriptPath = $data.transcript_path
    $cwd = $data.cwd
} catch {
    exit 0
}

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }
$waysDir = Join-Path $env:USERPROFILE ".claude\hooks\ways"
$winDir = Join-Path $waysDir "win"
$context = ""

# Load shared modules
. (Join-Path $winDir "detect-scope.ps1")
. (Join-Path $winDir "match-way.ps1")

$currentScope = Get-Scope $sessionId

function Get-TranscriptSize {
    if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
        return 0
    }
    return (Get-Item $transcriptPath).Length
}

function Test-Trigger {
    param(
        [string]$Trigger,
        [string]$WayFile
    )

    $content = Get-Content $WayFile -Raw

    switch ($Trigger) {
        "context-threshold" {
            $threshold = Get-FrontmatterField -Content $content -FieldName "threshold"
            if (-not $threshold) { $threshold = "90" }
            $thresholdInt = [int]$threshold

            # ~4 chars/token, ~155K window = 620K chars
            $limit = [int](620000 * $thresholdInt / 100)
            $size = Get-TranscriptSize

            return $size -gt $limit
        }
        "file-exists" {
            $pattern = Get-FrontmatterField -Content $content -FieldName "path"
            if (-not $pattern) { return $false }

            $searchPath = Join-Path $projectDir $pattern
            $matches = Get-ChildItem -Path $searchPath -ErrorAction SilentlyContinue | Select-Object -First 1
            return $null -ne $matches
        }
        "session-start" {
            return $true
        }
        default {
            return $false
        }
    }
}

function Scan-StateTriggers {
    param([string]$Dir)

    if (-not (Test-Path $Dir)) { return }

    $wayFiles = Get-ChildItem -Path $Dir -Filter "way.md" -Recurse -File -ErrorAction SilentlyContinue

    foreach ($wayFile in $wayFiles) {
        $wayPath = $wayFile.FullName.Substring($Dir.Length + 1)
        $wayPath = $wayPath -replace "\\way\.md$", ""
        $wayPath = $wayPath -replace "\\", "/"

        $content = Get-Content $wayFile.FullName -Raw

        # Check for trigger field
        $trigger = Get-FrontmatterField -Content $content -FieldName "trigger"
        if (-not $trigger) { continue }

        # Check scope
        $scope = Get-FrontmatterField -Content $content -FieldName "scope"
        if (-not $scope) { $scope = "agent" }
        if (-not (Test-ScopeMatch -ScopeField $scope -CurrentScope $currentScope)) {
            continue
        }

        # Evaluate trigger
        if (Test-Trigger -Trigger $trigger -WayFile $wayFile.FullName) {
            $showWayScript = Join-Path $winDir "show-way.ps1"
            if (Test-Path $showWayScript) {
                $output = & $showWayScript -Way $wayPath -SessionId $sessionId -Trigger "state"
                if ($output) {
                    $script:context += $output + "`n`n"
                }
            }
        }
    }
}

# Safety net: re-inject core if context was cleared
$coreMarker = Join-Path $env:TEMP ".claude-core-$sessionId"
if ($sessionId) {
    if (-not (Test-Path $coreMarker)) {
        $showCoreScript = Join-Path $winDir "show-core.ps1"
        if (Test-Path $showCoreScript) {
            $jsonInput = @{ session_id = $sessionId } | ConvertTo-Json -Compress
            $coreOutput = $jsonInput | & $showCoreScript
            if ($coreOutput) {
                $context += $coreOutput + "`n`n"
            }
        }
    } else {
        # Check for stale injection
        $ctxSize = Get-TranscriptSize
        $markerTs = [int](Get-Content $coreMarker -Raw)
        $nowTs = [int][double]::Parse((Get-Date -UFormat %s))
        $age = $nowTs - $markerTs

        if ($ctxSize -lt 5000 -and $age -gt 30) {
            Remove-Item $coreMarker -Force -ErrorAction SilentlyContinue
            $showCoreScript = Join-Path $winDir "show-core.ps1"
            if (Test-Path $showCoreScript) {
                $jsonInput = @{ session_id = $sessionId } | ConvertTo-Json -Compress
                $coreOutput = $jsonInput | & $showCoreScript
                if ($coreOutput) {
                    $context += $coreOutput + "`n`n"
                }
            }
        }
    }
}

# Scan project-local first, then global
$projectWays = Join-Path $projectDir ".claude\ways"
Scan-StateTriggers -Dir $projectWays
Scan-StateTriggers -Dir $waysDir

# Output accumulated context
if ($context.Trim()) {
    $result = @{ additionalContext = $context.TrimEnd("`n") } | ConvertTo-Json -Compress
    Write-Output $result
}
