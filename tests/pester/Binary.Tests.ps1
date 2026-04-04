#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Tests for the way-match binary on Windows

.DESCRIPTION
    Verifies that the way-match BM25 matching binary works correctly on Windows.
    The binary is an APE (Actually Portable Executable) built with Cosmopolitan.
#>

BeforeAll {
    Import-Module "$PSScriptRoot\TestHelpers.psm1" -Force
    $script:Binary = Get-WayMatchBinary
}

Describe "way-match Binary" {
    Context "Binary Availability" {
        It "Should find way-match binary in bin/" {
            $script:Binary | Should -Not -BeNullOrEmpty
        }

        It "Should have the binary file exist" {
            if ($script:Binary) {
                Test-Path $script:Binary | Should -BeTrue
            } else {
                Set-ItResult -Skipped -Because "Binary not found"
            }
        }
    }

    Context "Basic Execution" -Skip:(-not $script:Binary) {
        It "Should execute without error" {
            $result = & $script:Binary pair `
                --description "test" `
                --vocabulary "test" `
                --query "test" `
                --threshold 0.1 2>&1

            # Should complete (exit code 0 or 1, not error)
            $LASTEXITCODE | Should -BeIn @(0, 1)
        }

        It "Should show help with --help" {
            $result = & $script:Binary --help 2>&1
            $result | Should -Match "usage|Usage|USAGE"
        }
    }

    Context "BM25 Matching" -Skip:(-not $script:Binary) {
        It "Should match when query contains vocabulary words" {
            & $script:Binary pair `
                --description "GitHub pull requests and issues" `
                --vocabulary "github pr issue pullrequest review" `
                --query "help me create a pull request on github" `
                --threshold 1.0 2>&1 | Out-Null

            $LASTEXITCODE | Should -Be 0 -Because "Query contains matching vocabulary"
        }

        It "Should not match unrelated queries" {
            & $script:Binary pair `
                --description "GitHub pull requests and issues" `
                --vocabulary "github pr issue pullrequest" `
                --query "what is the weather today" `
                --threshold 2.0 2>&1 | Out-Null

            $LASTEXITCODE | Should -Be 1 -Because "Query is unrelated"
        }

        It "Should respect threshold setting" {
            # High threshold should not match
            & $script:Binary pair `
                --description "testing" `
                --vocabulary "test" `
                --query "test" `
                --threshold 100.0 2>&1 | Out-Null

            $LASTEXITCODE | Should -Be 1 -Because "Threshold too high"

            # Low threshold should match
            & $script:Binary pair `
                --description "testing" `
                --vocabulary "test" `
                --query "test" `
                --threshold 0.1 2>&1 | Out-Null

            $LASTEXITCODE | Should -Be 0 -Because "Threshold is low"
        }

        It "Should handle Porter2 stemming (commit -> commit, committing -> commit)" {
            # "committing" should stem to "commit" and match
            & $script:Binary pair `
                --description "git commit workflow" `
                --vocabulary "commit commits committed committing" `
                --query "I am committing my changes" `
                --threshold 1.0 2>&1 | Out-Null

            $LASTEXITCODE | Should -Be 0 -Because "Porter2 stemming should match 'committing' to 'commit'"
        }
    }

    Context "Edge Cases" -Skip:(-not $script:Binary) {
        It "Should handle empty query gracefully" {
            & $script:Binary pair `
                --description "test" `
                --vocabulary "test" `
                --query "" `
                --threshold 1.0 2>&1 | Out-Null

            # Should not crash, just not match
            $LASTEXITCODE | Should -BeIn @(0, 1)
        }

        It "Should handle special characters in query" {
            & $script:Binary pair `
                --description "test description" `
                --vocabulary "test" `
                --query "test @#$%^&*() special chars" `
                --threshold 1.0 2>&1 | Out-Null

            # Should not crash
            $LASTEXITCODE | Should -BeIn @(0, 1)
        }

        It "Should handle Unicode/non-ASCII characters" {
            & $script:Binary pair `
                --description "test description" `
                --vocabulary "test" `
                --query "test with unicode: cafe resume naive" `
                --threshold 0.5 2>&1 | Out-Null

            $LASTEXITCODE | Should -BeIn @(0, 1)
        }

        It "Should handle very long queries" {
            $longQuery = "test " * 500  # 2500+ characters
            & $script:Binary pair `
                --description "test" `
                --vocabulary "test" `
                --query $longQuery `
                --threshold 1.0 2>&1 | Out-Null

            $LASTEXITCODE | Should -BeIn @(0, 1)
        }
    }

    Context "Real Way Matching" -Skip:(-not $script:Binary) {
        It "Should match GitHub way with PR-related prompt" {
            $githubWay = Join-Path (Get-HooksDir) "softwaredev\delivery\github\way.md"

            if (Test-Path $githubWay) {
                $description = Get-WayFrontmatter -WayFile $githubWay -Field "description"
                $vocabulary = Get-WayFrontmatter -WayFile $githubWay -Field "vocabulary"
                $threshold = Get-WayFrontmatter -WayFile $githubWay -Field "threshold"

                if ($description -and $vocabulary) {
                    & $script:Binary pair `
                        --description $description `
                        --vocabulary $vocabulary `
                        --query "create a pull request for this feature" `
                        --threshold ($threshold ?? "2.0") 2>&1 | Out-Null

                    $LASTEXITCODE | Should -Be 0 -Because "GitHub way should match PR prompt"
                } else {
                    Set-ItResult -Skipped -Because "Could not parse GitHub way frontmatter"
                }
            } else {
                Set-ItResult -Skipped -Because "GitHub way.md not found"
            }
        }

        It "Should match commit way with commit-related prompt" {
            $commitWay = Join-Path (Get-HooksDir) "softwaredev\delivery\commits\way.md"

            if (Test-Path $commitWay) {
                $description = Get-WayFrontmatter -WayFile $commitWay -Field "description"
                $vocabulary = Get-WayFrontmatter -WayFile $commitWay -Field "vocabulary"
                $threshold = Get-WayFrontmatter -WayFile $commitWay -Field "threshold"

                if ($description -and $vocabulary) {
                    & $script:Binary pair `
                        --description $description `
                        --vocabulary $vocabulary `
                        --query "help me write a commit message for my changes" `
                        --threshold ($threshold ?? "2.0") 2>&1 | Out-Null

                    $LASTEXITCODE | Should -Be 0 -Because "Commit way should match commit prompt"
                } else {
                    Set-ItResult -Skipped -Because "Could not parse commit way frontmatter"
                }
            } else {
                Set-ItResult -Skipped -Because "Commit way.md not found"
            }
        }
    }
}
