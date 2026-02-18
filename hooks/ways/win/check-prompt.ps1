# Check user prompts for keywords from way frontmatter
#
# TRIGGER FLOW:
# UserPromptSubmit -> scan_ways() -> show-way.ps1 (idempotent)
#
# Ways are nested: domain/wayname/way.md
# Matching is ADDITIVE: pattern (regex/keyword) and semantic are OR'd.
# Project-local ways are scanned first (and take precedence).

param()

# Read JSON from stdin
$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $prompt = ($data.prompt).ToLower()
    $sessionId = $data.session_id
    $cwd = $data.cwd
} catch {
    exit 0
}

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $cwd }
$waysDir = Join-Path $env:USERPROFILE ".claude\hooks\ways"
$winDir = Join-Path $waysDir "win"

# Load shared modules
. (Join-Path $winDir "detect-scope.ps1")
. (Join-Path $winDir "match-way.ps1")

Initialize-SemanticEngine
$currentScope = Get-Scope $sessionId

# Read response topics from Stop hook (if available)
$responseState = Join-Path $env:TEMP "claude-response-topics-$sessionId"
$responseTopics = ""
if (Test-Path $responseState) {
    try {
        $stateData = Get-Content $responseState -Raw | ConvertFrom-Json
        $responseTopics = $stateData.topics
    } catch {}
}

$combinedContext = "$prompt $responseTopics"

function Scan-Ways {
    param([string]$Dir)

    if (-not (Test-Path $Dir)) { return }

    $wayFiles = Get-ChildItem -Path $Dir -Filter "way.md" -Recurse -File -ErrorAction SilentlyContinue

    foreach ($wayFile in $wayFiles) {
        # Extract way path relative to ways dir
        $wayPath = $wayFile.FullName.Substring($Dir.Length + 1)
        $wayPath = $wayPath -replace "\\way\.md$", ""
        $wayPath = $wayPath -replace "\\", "/"

        # Read way file
        $content = Get-Content $wayFile.FullName -Raw

        # Extract frontmatter fields
        $pattern = Get-FrontmatterField -Content $content -FieldName "pattern"
        $description = Get-FrontmatterField -Content $content -FieldName "description"
        $vocabulary = Get-FrontmatterField -Content $content -FieldName "vocabulary"
        $threshold = Get-FrontmatterField -Content $content -FieldName "threshold"
        $scope = Get-FrontmatterField -Content $content -FieldName "scope"
        if (-not $scope) { $scope = "agent" }

        # Check scope
        if (-not (Test-ScopeMatch -ScopeField $scope -CurrentScope $currentScope)) {
            continue
        }

        # Parse threshold
        $thresholdVal = 2.0
        if ($threshold) {
            try { $thresholdVal = [double]$threshold } catch {}
        }

        # Additive matching
        if (Test-WayMatch -Prompt $prompt -Pattern $pattern -Description $description -Vocabulary $vocabulary -Threshold $thresholdVal) {
            # Call show-way.ps1
            $showWayScript = Join-Path $winDir "show-way.ps1"
            if (Test-Path $showWayScript) {
                & $showWayScript -Way $wayPath -SessionId $sessionId -Trigger "prompt"
            }
        }
    }
}

# Scan project-local first, then global
$projectWays = Join-Path $projectDir ".claude\ways"
Scan-Ways -Dir $projectWays
Scan-Ways -Dir $waysDir
