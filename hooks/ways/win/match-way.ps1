# Shared matching logic for ways - sourced by check-prompt.ps1 and check-task-pre.ps1
#
# Usage:
#   . $PSScriptRoot\match-way.ps1
#   Initialize-SemanticEngine
#   Test-WayMatch -Prompt $prompt -Pattern $pattern -Description $desc -Vocabulary $vocab -Threshold $thresh

$script:SemanticEngine = "none"
$script:WayMatchBin = ""

function Initialize-SemanticEngine {
    $script:WayMatchBin = Join-Path $env:USERPROFILE ".claude\bin\way-match.exe"

    if (Test-Path $script:WayMatchBin) {
        $script:SemanticEngine = "bm25"
    } else {
        # Check for gzip (from Git Bash or standalone)
        $gzipPath = Get-Command gzip -ErrorAction SilentlyContinue
        if ($gzipPath) {
            $script:SemanticEngine = "ncd"
        } else {
            $script:SemanticEngine = "none"
        }
    }
}

# Additive matching: pattern OR semantic (either channel can fire)
function Test-WayMatch {
    param(
        [string]$Prompt,
        [string]$Pattern,
        [string]$Description,
        [string]$Vocabulary,
        [double]$Threshold = 2.0
    )

    # Channel 1: Regex pattern match
    if ($Pattern -and ($Prompt -match $Pattern)) {
        return $true
    }

    # Channel 2: Semantic match (only if description+vocabulary present)
    if ($Description -and $Vocabulary) {
        switch ($script:SemanticEngine) {
            "bm25" {
                try {
                    $result = & $script:WayMatchBin pair `
                        --description $Description `
                        --vocabulary $Vocabulary `
                        --query $Prompt `
                        --threshold $Threshold 2>$null
                    if ($LASTEXITCODE -eq 0) {
                        return $true
                    }
                } catch {}
            }
            "ncd" {
                # Use semantic-match.ps1 for NCD fallback
                $semanticScript = Join-Path $PSScriptRoot "semantic-match.ps1"
                if (Test-Path $semanticScript) {
                    try {
                        $result = & $semanticScript -Prompt $Prompt -Description $Description -Vocabulary $Vocabulary -Threshold 0.58 2>$null
                        if ($LASTEXITCODE -eq 0) {
                            return $true
                        }
                    } catch {}
                }
            }
        }
    }

    return $false
}

# Extract frontmatter field from way file content
function Get-FrontmatterField {
    param(
        [string]$Content,
        [string]$FieldName
    )

    # Match field in frontmatter (between first pair of ---)
    $lines = $Content -split "`n"
    $inFrontmatter = $false
    $frontmatterStarted = $false

    foreach ($line in $lines) {
        if ($line -match '^---\s*$') {
            if (-not $frontmatterStarted) {
                $frontmatterStarted = $true
                $inFrontmatter = $true
                continue
            } else {
                break
            }
        }

        if ($inFrontmatter -and $line -match "^${FieldName}:\s*(.*)$") {
            return $Matches[1].Trim()
        }
    }

    return ""
}

# Strip frontmatter from way content
function Remove-Frontmatter {
    param([string]$Content)

    $lines = $Content -split "`n"
    $output = @()
    $fmCount = 0

    foreach ($line in $lines) {
        if ($line -match '^---\s*$') {
            $fmCount++
            continue
        }
        if ($fmCount -ge 2 -or ($fmCount -eq 0)) {
            $output += $line
        }
    }

    # If we never saw frontmatter, return original (minus any accidental stripping)
    if ($fmCount -lt 2) {
        # Skip first --- block only
        $lines = $Content -split "`n"
        $output = @()
        $skip = $false
        $skipped = $false

        foreach ($line in $lines) {
            if ($line -match '^---\s*$' -and -not $skipped) {
                $skip = -not $skip
                if (-not $skip) { $skipped = $true }
                continue
            }
            if (-not $skip) {
                $output += $line
            }
        }
    }

    return ($output -join "`n")
}
