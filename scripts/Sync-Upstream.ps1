#Requires -Version 5.1
<#
.SYNOPSIS
    Syncs changes from upstream aaronsb/claude-code-config repository.

.DESCRIPTION
    This script automates the process of syncing upstream changes while
    maintaining Windows/PowerShell compatibility. It handles:
    - Data file syncing (ways, docs) - fully automated
    - Simple script changes - automated transforms
    - Complex script changes - flagged for manual review

.PARAMETER Auto
    Run in non-interactive mode (for CI/CD)

.PARAMETER DryRun
    Show what would be done without making changes

.PARAMETER SkipTests
    Skip running tests after sync

.EXAMPLE
    .\Sync-Upstream.ps1
    Interactive sync with prompts

.EXAMPLE
    .\Sync-Upstream.ps1 -Auto
    Non-interactive sync for CI/CD
#>

[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$DryRun,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Configuration
$UpstreamRepo = "aaronsb/claude-code-config"
$UpstreamBranch = "main"
$ScriptRoot = Split-Path -Parent $PSScriptRoot
$WaysDir = Join-Path $ScriptRoot "hooks\ways"
$WinDir = Join-Path $WaysDir "win"

# Colors for output
function Write-Step { param($msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "  [X] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "  $msg" -ForegroundColor Gray }

# ============================================================================
# STEP 1: Verify Git Setup
# ============================================================================
Write-Step "Verifying Git setup"

Set-Location $ScriptRoot

# Check if we're in a git repo
if (-not (Test-Path ".git")) {
    Write-Error "Not a git repository. Run from the claude-code-config directory."
    exit 1
}
Write-Success "Git repository found"

# Check for upstream remote
$remotes = git remote -v 2>&1
if ($remotes -notmatch "upstream") {
    Write-Info "Adding upstream remote..."
    if (-not $DryRun) {
        git remote add upstream "https://github.com/$UpstreamRepo.git"
    }
    Write-Success "Upstream remote added"
} else {
    Write-Success "Upstream remote exists"
}

# Fetch upstream
Write-Info "Fetching upstream changes..."
if (-not $DryRun) {
    git fetch upstream $UpstreamBranch 2>&1 | Out-Null
}
Write-Success "Upstream fetched"

# ============================================================================
# STEP 2: Analyze Changes
# ============================================================================
Write-Step "Analyzing upstream changes"

# Get list of changed files
$changedFiles = git diff HEAD..upstream/$UpstreamBranch --name-only 2>&1

if ([string]::IsNullOrWhiteSpace($changedFiles)) {
    Write-Success "Already up to date with upstream!"
    exit 0
}

# Categorize changes
$dataFiles = @()
$simpleScripts = @()
$complexScripts = @()
$newScripts = @()
$otherFiles = @()

foreach ($file in $changedFiles) {
    if ([string]::IsNullOrWhiteSpace($file)) { continue }

    # Data files (ways, docs, governance)
    if ($file -match "way\.md$" -or $file -match "^docs/" -or $file -match "^governance/") {
        $dataFiles += $file
    }
    # Shell scripts in hooks/ways
    elseif ($file -match "hooks/ways/[^/]+\.sh$") {
        # Check if this is a new file or existing
        $localPath = Join-Path $ScriptRoot $file
        $psEquivalent = $file -replace '\.sh$', '.ps1' -replace 'hooks/ways/', 'hooks/ways/win/'
        $psPath = Join-Path $ScriptRoot $psEquivalent

        if (-not (Test-Path $localPath)) {
            $newScripts += $file
        } else {
            # Check diff size to categorize as simple or complex
            $diffLines = (git diff HEAD..upstream/$UpstreamBranch -- $file | Measure-Object -Line).Lines
            if ($diffLines -lt 30) {
                $simpleScripts += $file
            } else {
                $complexScripts += $file
            }
        }
    }
    else {
        $otherFiles += $file
    }
}

# Display summary
Write-Host ""
Write-Host "  Change Summary:" -ForegroundColor White
Write-Host "  ---------------"
Write-Info "  Data files (auto-sync):     $($dataFiles.Count)"
Write-Info "  Simple script changes:      $($simpleScripts.Count)"
Write-Info "  Complex script changes:     $($complexScripts.Count)"
Write-Info "  New scripts (need PS port): $($newScripts.Count)"
Write-Info "  Other files:                $($otherFiles.Count)"

if ($complexScripts.Count -gt 0 -or $newScripts.Count -gt 0) {
    Write-Warning "Manual attention required for complex/new scripts"
}

# ============================================================================
# STEP 3: Create Sync Branch
# ============================================================================
Write-Step "Creating sync branch"

$branchName = "upstream-sync-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

if (-not $DryRun) {
    # Stash any local changes
    $stashResult = git stash push -m "Pre-sync stash" 2>&1
    $hasStash = $stashResult -notmatch "No local changes"

    # Create and checkout branch
    git checkout -b $branchName 2>&1 | Out-Null
}

Write-Success "Created branch: $branchName"

# ============================================================================
# STEP 4: Sync Data Files
# ============================================================================
if ($dataFiles.Count -gt 0) {
    Write-Step "Syncing data files ($($dataFiles.Count) files)"

    foreach ($file in $dataFiles) {
        Write-Info "  $file"
        if (-not $DryRun) {
            git checkout upstream/$UpstreamBranch -- $file 2>&1 | Out-Null
        }
    }

    if (-not $DryRun) {
        git add -A 2>&1 | Out-Null
        git commit -m "chore: sync data files from upstream" --allow-empty 2>&1 | Out-Null
    }
    Write-Success "Data files synced"
}

# ============================================================================
# STEP 5: Apply Simple Script Transforms
# ============================================================================
if ($simpleScripts.Count -gt 0) {
    Write-Step "Processing simple script changes ($($simpleScripts.Count) files)"

    foreach ($script in $simpleScripts) {
        $scriptName = Split-Path -Leaf $script
        $psScript = $scriptName -replace '\.sh$', '.ps1'
        $psPath = Join-Path $WinDir $psScript

        Write-Info "  $scriptName"

        # Sync the bash script
        if (-not $DryRun) {
            git checkout upstream/$UpstreamBranch -- $script 2>&1 | Out-Null
        }

        # Check if PS equivalent exists
        if (Test-Path $psPath) {
            Write-Info "    -> PowerShell equivalent exists, may need update"
        } else {
            Write-Warning "    -> No PowerShell equivalent found!"
        }
    }

    if (-not $DryRun) {
        git add -A 2>&1 | Out-Null
        git commit -m "chore: sync simple script changes from upstream" --allow-empty 2>&1 | Out-Null
    }
    Write-Success "Simple scripts synced"
}

# ============================================================================
# STEP 6: Flag Complex Changes
# ============================================================================
if ($complexScripts.Count -gt 0 -or $newScripts.Count -gt 0) {
    Write-Step "Flagging complex changes for manual review"

    $flagFile = Join-Path $ScriptRoot "SYNC_REVIEW_REQUIRED.md"

    $flagContent = @"
# Sync Review Required

This sync from upstream requires manual attention for the following files:

## Complex Script Changes (need PowerShell port updates)

These bash scripts have significant changes that need to be ported to their
PowerShell equivalents in ``hooks/ways/win/``.

"@

    foreach ($script in $complexScripts) {
        $scriptName = Split-Path -Leaf $script
        $psScript = $scriptName -replace '\.sh$', '.ps1'
        $flagContent += "- [ ] ``$script`` -> ``hooks/ways/win/$psScript```n"
    }

    $flagContent += @"

## New Scripts (need new PowerShell ports)

These are new bash scripts that need complete PowerShell equivalents created.

"@

    foreach ($script in $newScripts) {
        $scriptName = Split-Path -Leaf $script
        $psScript = $scriptName -replace '\.sh$', '.ps1'
        $flagContent += "- [ ] ``$script`` -> ``hooks/ways/win/$psScript`` (NEW)`n"
    }

    $flagContent += @"

## How to Complete This Sync

1. For each file above, review the bash script changes:
   ``````
   git diff HEAD~1 -- hooks/ways/{script}.sh
   ``````

2. Update or create the PowerShell equivalent using patterns in ``pc-refactor.md``

3. Run tests to verify:
   ``````
   Invoke-Pester -Path .\tests
   ``````

4. Delete this file and commit:
   ``````
   Remove-Item SYNC_REVIEW_REQUIRED.md
   git add -A && git commit -m "chore: complete PowerShell port for upstream sync"
   ``````

5. Create PR or merge to main

---
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

    if (-not $DryRun) {
        $flagContent | Out-File -FilePath $flagFile -Encoding utf8

        # Also sync the bash scripts
        foreach ($script in ($complexScripts + $newScripts)) {
            git checkout upstream/$UpstreamBranch -- $script 2>&1 | Out-Null
        }

        git add -A 2>&1 | Out-Null
        git commit -m "chore: sync complex scripts (REVIEW REQUIRED)" --allow-empty 2>&1 | Out-Null
    }

    Write-Warning "Created SYNC_REVIEW_REQUIRED.md - manual porting needed"
}

# ============================================================================
# STEP 7: Sync Other Files
# ============================================================================
if ($otherFiles.Count -gt 0) {
    Write-Step "Syncing other files ($($otherFiles.Count) files)"

    foreach ($file in $otherFiles) {
        # Skip Windows-specific files that shouldn't be overwritten
        if ($file -match "settings\.windows\.json" -or
            $file -match "hooks/ways/win/" -or
            $file -match "\.ps1$") {
            Write-Info "  [SKIP] $file (Windows-specific)"
            continue
        }

        Write-Info "  $file"
        if (-not $DryRun) {
            git checkout upstream/$UpstreamBranch -- $file 2>&1 | Out-Null
        }
    }

    if (-not $DryRun) {
        git add -A 2>&1 | Out-Null
        git commit -m "chore: sync other files from upstream" --allow-empty 2>&1 | Out-Null
    }
    Write-Success "Other files synced"
}

# ============================================================================
# STEP 8: Run Tests
# ============================================================================
if (-not $SkipTests) {
    Write-Step "Running tests"

    $testsPath = Join-Path $ScriptRoot "tests"
    if (Test-Path $testsPath) {
        if (-not $DryRun) {
            try {
                $testResult = Invoke-Pester -Path $testsPath -PassThru -Output Minimal
                if ($testResult.FailedCount -gt 0) {
                    Write-Warning "Some tests failed - review before merging"
                } else {
                    Write-Success "All tests passed!"
                }
            } catch {
                Write-Warning "Pester not installed or test error: $_"
            }
        }
    } else {
        Write-Info "No tests directory found"
    }
}

# ============================================================================
# STEP 9: Summary
# ============================================================================
Write-Step "Sync Complete"

Write-Host ""
Write-Host "  Branch: $branchName" -ForegroundColor White
Write-Host ""

if ($complexScripts.Count -gt 0 -or $newScripts.Count -gt 0) {
    Write-Host "  Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Review SYNC_REVIEW_REQUIRED.md"
    Write-Host "  2. Port complex changes to PowerShell (see pc-refactor.md)"
    Write-Host "  3. Run tests: Invoke-Pester -Path .\tests"
    Write-Host "  4. Create PR or merge to main"
} else {
    Write-Host "  All changes were automatically processed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  To complete:"
    Write-Host "  - Review changes: git log --oneline HEAD~5..HEAD"
    Write-Host "  - Create PR: gh pr create"
    Write-Host "  - Or merge directly: git checkout main && git merge $branchName"
}

Write-Host ""

# Restore stash if we had one
if (-not $DryRun -and $hasStash) {
    Write-Info "Restoring stashed changes..."
    git stash pop 2>&1 | Out-Null
}
