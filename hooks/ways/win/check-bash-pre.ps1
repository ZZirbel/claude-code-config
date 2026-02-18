# PreToolUse: Check bash commands against way frontmatter
#
# TRIGGER FLOW:
# PreToolUse:Bash -> scan_ways() -> show-way.ps1 (idempotent)
#
# Ways are nested: domain/wayname/way.md
# Multiple ways can match a single command - CONTEXT accumulates.

param()

# Read JSON from stdin
$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $cmd = $data.tool_input.command
    $desc = ($data.tool_input.description).ToLower()
    $sessionId = $data.session_id
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

function Scan-Ways {
    param([string]$Dir)

    if (-not (Test-Path $Dir)) { return }

    $wayFiles = Get-ChildItem -Path $Dir -Filter "way.md" -Recurse -File -ErrorAction SilentlyContinue

    foreach ($wayFile in $wayFiles) {
        $wayPath = $wayFile.FullName.Substring($Dir.Length + 1)
        $wayPath = $wayPath -replace "\\way\.md$", ""
        $wayPath = $wayPath -replace "\\", "/"

        $content = Get-Content $wayFile.FullName -Raw

        # Extract frontmatter fields
        $commands = Get-FrontmatterField -Content $content -FieldName "commands"
        $pattern = Get-FrontmatterField -Content $content -FieldName "pattern"

        # Check scope
        $scope = Get-FrontmatterField -Content $content -FieldName "scope"
        if (-not $scope) { $scope = "agent" }
        if (-not (Test-ScopeMatch -ScopeField $scope -CurrentScope $currentScope)) {
            continue
        }

        $matched = $false

        # Check command patterns
        if ($commands -and $cmd -and ($cmd -match $commands)) {
            $matched = $true
        }

        # Check description against pattern
        if ($desc -and $pattern -and ($desc -match $pattern)) {
            $matched = $true
        }

        if ($matched) {
            $showWayScript = Join-Path $winDir "show-way.ps1"
            if (Test-Path $showWayScript) {
                $output = & $showWayScript -Way $wayPath -SessionId $sessionId -Trigger "bash"
                if ($output) {
                    $script:context += $output
                }
            }
        }
    }
}

# Scan project-local first, then global
$projectWays = Join-Path $projectDir ".claude\ways"
Scan-Ways -Dir $projectWays
Scan-Ways -Dir $waysDir

# Output JSON - PreToolUse format
if ($context) {
    $result = @{
        decision = "approve"
        additionalContext = $context
    } | ConvertTo-Json -Compress
    Write-Output $result
}
