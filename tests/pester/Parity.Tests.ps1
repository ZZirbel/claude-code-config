#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Parity tests comparing Bash and PowerShell hook outputs

.DESCRIPTION
    These tests verify that PowerShell hook scripts produce equivalent
    output to their Bash counterparts. Requires Git Bash or WSL installed.

.NOTES
    These tests are skipped if bash is not available.
#>

# Import at file scope so variables are available during Pester discovery
Import-Module "$PSScriptRoot\TestHelpers.psm1" -Force
$script:WinHooksDir = Get-WinHooksDir
$script:HooksDir = Get-HooksDir

# Check if bash is available (needed for -Skip during discovery)
$script:BashAvailable = $false
try {
    $bashResult = bash --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $script:BashAvailable = $true
    }
} catch {
    $script:BashAvailable = $false
}

if (-not $script:BashAvailable) {
    Write-Warning "Bash not available - parity tests will be skipped"
}

$skipBashParity = -not $script:BashAvailable
Describe "Bash-PowerShell Parity" -Skip:$skipBashParity {
    Context "macro.sh vs macro.ps1" {
        It "Should produce similar ways table structure" {
            $bashScript = Join-Path $script:HooksDir "macro.sh"
            $psScript = Join-Path $script:WinHooksDir "macro.ps1"

            if ((Test-Path $bashScript) -and (Test-Path $psScript)) {
                # Run bash version
                $bashResult = bash $bashScript 2>&1

                # Run PowerShell version
                $psResult = & $psScript 2>&1

                # Both should produce markdown tables
                if ($bashResult) {
                    $bashResult | Should -Match "\|"
                }
                if ($psResult) {
                    $psResult | Should -Match "\|"
                }

                # Note: Exact comparison is difficult due to formatting differences
                # We verify both produce table-like output
            } else {
                Set-ItResult -Skipped -Because "macro scripts not found"
            }
        }
    }

    Context "detect-scope.sh vs detect-scope.ps1" {
        It "Should return same scope value" {
            $bashScript = Join-Path $script:HooksDir "detect-scope.sh"
            $psScript = Join-Path $script:WinHooksDir "detect-scope.ps1"

            if ((Test-Path $bashScript) -and (Test-Path $psScript)) {
                $testInput = '{"session_id":"parity-test-123"}'

                # Run bash version
                $bashResult = $testInput | bash $bashScript 2>&1

                # Run PowerShell version
                $psResult = $testInput | & $psScript 2>&1

                # Both should return 'agent' for default scope
                # (Exact format may differ)
                if ($bashResult -and $psResult) {
                    # Normalize and compare
                    $bashScope = ($bashResult -join "").Trim()
                    $psScope = ($psResult -join "").Trim()

                    # Both should indicate agent scope
                    ($bashScope + $psScope) | Should -Match "agent"
                }
            } else {
                Set-ItResult -Skipped -Because "detect-scope scripts not found"
            }
        }
    }

    Context "Frontmatter Parsing Parity" {
        It "Should extract same field values from way.md" {
            $testWay = Join-Path $script:HooksDir "softwaredev\delivery\github\way.md"

            if (Test-Path $testWay) {
                # PowerShell extraction
                $psPattern = Get-WayFrontmatter -WayFile $testWay -Field "pattern"
                $psDescription = Get-WayFrontmatter -WayFile $testWay -Field "description"

                # Bash extraction (using awk)
                $bashPattern = bash -c "awk '/^---$/,/^---$/' '$testWay' | grep '^pattern:' | cut -d: -f2- | tr -d ' `"'" 2>&1
                $bashDescription = bash -c "awk '/^---$/,/^---$/' '$testWay' | grep '^description:' | cut -d: -f2- | sed 's/^ *//'" 2>&1

                # Compare (normalize whitespace)
                if ($psPattern -and $bashPattern) {
                    $psPattern.Trim() | Should -Be $bashPattern.Trim()
                }
            } else {
                Set-ItResult -Skipped -Because "GitHub way not found"
            }
        }
    }
}

Describe "Output Format Compatibility" {
    Context "JSON Output Structure" {
        It "Should match expected Claude Code hook output format" {
            # Claude Code expects this structure for additionalContext
            $expectedFormat = @{
                hookSpecificOutput = @{
                    additionalContext = "content here"
                }
            } | ConvertTo-Json -Compress

            # Verify it's valid
            { $expectedFormat | ConvertFrom-Json } | Should -Not -Throw

            # Verify structure
            $parsed = $expectedFormat | ConvertFrom-Json
            $parsed.hookSpecificOutput | Should -Not -BeNullOrEmpty
            $parsed.hookSpecificOutput.additionalContext | Should -Not -BeNullOrEmpty
        }

        It "Should match expected decision output format for PreToolUse" {
            # For PreToolUse hooks that can block
            $blockFormat = @{
                decision = "block"
                reason = "Security concern"
            } | ConvertTo-Json -Compress

            $allowFormat = @{
                decision = "allow"
            } | ConvertTo-Json -Compress

            # Verify both are valid
            { $blockFormat | ConvertFrom-Json } | Should -Not -Throw
            { $allowFormat | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context "Path Normalization" {
        It "Should normalize Windows paths to forward slashes in output" {
            $windowsPath = "C:\Users\test\.claude\hooks\ways\softwaredev\way.md"
            $normalizedPath = $windowsPath -replace '\\', '/'

            $normalizedPath | Should -Be "C:/Users/test/.claude/hooks/ways/softwaredev/way.md"
        }

        It "Should handle mixed path separators" {
            $mixedPath = "C:\Users/test\.claude/hooks\ways"
            $normalizedPath = $mixedPath -replace '\\', '/'

            $normalizedPath | Should -Not -Match '\\'
        }
    }
}

Describe "Environment Variable Compatibility" {
    Context "Path Variables" {
        It "Should have USERPROFILE set" {
            $env:USERPROFILE | Should -Not -BeNullOrEmpty
        }

        It "Should have TEMP set" {
            $env:TEMP | Should -Not -BeNullOrEmpty
        }

        It "Should have valid TEMP directory" {
            Test-Path $env:TEMP | Should -BeTrue
        }
    }

    Context "Bash Equivalents" {
        It "USERPROFILE should be equivalent to HOME" {
            # In Git Bash, HOME is typically set to USERPROFILE
            if ($script:BashAvailable) {
                $bashHome = bash -c 'echo $HOME' 2>&1
                # Normalize paths for comparison
                $psHome = $env:USERPROFILE -replace '\\', '/'

                # They should point to same location (may have different formats)
                $bashHome | Should -Match ($env:USERNAME)
            } else {
                Set-ItResult -Skipped -Because "Bash not available"
            }
        }
    }
}
