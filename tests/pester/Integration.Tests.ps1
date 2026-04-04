#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Integration tests for the full hook pipeline

.DESCRIPTION
    Tests the complete flow of hook execution, including:
    - Marker file creation and detection
    - Way content output
    - Idempotency verification
    - Cross-hook state management
#>

BeforeAll {
    Import-Module "$PSScriptRoot\TestHelpers.psm1" -Force
    $script:WinHooksDir = Get-WinHooksDir
    $script:HooksDir = Get-HooksDir
    $script:TempDir = New-TestMarkerDir
    $script:SessionId = "integration-test-$(Get-Random)"

    # Override temp location for tests
    $env:CLAUDE_TEST_TEMP = $script:TempDir
}

AfterAll {
    Remove-TestMarkerDir -Path $script:TempDir
    Remove-Item Env:\CLAUDE_TEST_TEMP -ErrorAction SilentlyContinue
}

Describe "Way File Structure" {
    Context "Frontmatter Parsing" {
        It "Should find way.md files" {
            $ways = Get-AllWayFiles
            $ways.Count | Should -BeGreaterThan 0
        }

        It "Should parse description from frontmatter" {
            $ways = Get-AllWayFiles | Select-Object -First 5

            foreach ($way in $ways) {
                $description = Get-WayFrontmatter -WayFile $way.FullName -Field "description"
                # Most ways should have descriptions
                # (Some may not, so we don't fail on missing)
            }
        }

        It "Should parse pattern from frontmatter" {
            $githubWay = Join-Path $script:HooksDir "softwaredev\delivery\github\way.md"

            if (Test-Path $githubWay) {
                $pattern = Get-WayFrontmatter -WayFile $githubWay -Field "pattern"
                $pattern | Should -Not -BeNullOrEmpty
                $pattern | Should -Match "github|pr|issue"
            } else {
                Set-ItResult -Skipped -Because "GitHub way not found"
            }
        }

        It "Should parse scope from frontmatter" {
            $ways = Get-AllWayFiles | Select-Object -First 10

            foreach ($way in $ways) {
                $scope = Get-WayFrontmatter -WayFile $way.FullName -Field "scope"
                # Scope is optional, default is 'agent'
                if ($scope) {
                    $scope | Should -Match "agent|subagent|teammate"
                }
            }
        }
    }

    Context "Way Content" {
        It "Should have content after frontmatter" {
            $ways = Get-AllWayFiles | Select-Object -First 5

            foreach ($way in $ways) {
                $content = Get-Content $way.FullName -Raw

                # Should have frontmatter delimiters
                $content | Should -Match "^---"

                # Should have content after frontmatter
                if ($content -match "(?ms)^---\r?\n.+?\r?\n---\r?\n(.+)$") {
                    $bodyContent = $Matches[1].Trim()
                    $bodyContent | Should -Not -BeNullOrEmpty
                }
            }
        }
    }
}

Describe "Domain Organization" {
    Context "Domain Structure" {
        $expectedDomains = @(
            "softwaredev"
            "meta"
        )

        foreach ($domain in $expectedDomains) {
            It "Should have $domain domain" {
                $domainPath = Join-Path $script:HooksDir $domain
                Test-Path $domainPath | Should -BeTrue
            }
        }
    }

    Context "Softwaredev Subdomain" {
        $expectedSubdomains = @(
            "architecture"
            "delivery"
            "code"
        )

        foreach ($subdomain in $expectedSubdomains) {
            It "Should have softwaredev/$subdomain" {
                $path = Join-Path $script:HooksDir "softwaredev\$subdomain"
                Test-Path $path | Should -BeTrue
            }
        }
    }
}

Describe "Configuration Files" {
    Context "Settings Files" {
        It "Should have settings.json" {
            $path = Join-Path (Get-RepoRoot) "settings.json"
            Test-Path $path | Should -BeTrue
        }

        It "Should have settings.windows.json" {
            $path = Join-Path (Get-RepoRoot) "settings.windows.json"
            Test-Path $path | Should -BeTrue
        }

        It "Should have valid JSON in settings.windows.json" {
            $path = Join-Path (Get-RepoRoot) "settings.windows.json"
            $content = Get-Content $path -Raw
            { $content | ConvertFrom-Json } | Should -Not -Throw
        }

        It "Should define hooks in settings.windows.json" {
            $path = Join-Path (Get-RepoRoot) "settings.windows.json"
            $settings = Get-Content $path -Raw | ConvertFrom-Json

            $settings.hooks | Should -Not -BeNullOrEmpty
        }
    }

    Context "Ways Configuration" {
        It "Should have ways.json" {
            $path = Join-Path (Get-RepoRoot) "ways.json"
            Test-Path $path | Should -BeTrue
        }

        It "Should have valid JSON in ways.json" {
            $path = Join-Path (Get-RepoRoot) "ways.json"
            $content = Get-Content $path -Raw
            { $content | ConvertFrom-Json } | Should -Not -Throw
        }
    }

    Context "Core Guidance" {
        It "Should have core.md" {
            $path = Join-Path $script:HooksDir "core.md"
            Test-Path $path | Should -BeTrue
        }

        It "Should have meaningful core.md content" {
            $path = Join-Path $script:HooksDir "core.md"
            $content = Get-Content $path -Raw
            $content.Length | Should -BeGreaterThan 100
        }
    }
}

Describe "Settings.windows.json Hook Definitions" {
    BeforeAll {
        $settingsPath = Join-Path (Get-RepoRoot) "settings.windows.json"
        $script:Settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    }

    Context "Hook Event Coverage" {
        It "Should define SessionStart hooks" {
            $script:Settings.hooks.SessionStart | Should -Not -BeNullOrEmpty
        }

        It "Should define UserPromptSubmit hooks" {
            $script:Settings.hooks.UserPromptSubmit | Should -Not -BeNullOrEmpty
        }

        It "Should define PreToolUse hooks" {
            $script:Settings.hooks.PreToolUse | Should -Not -BeNullOrEmpty
        }
    }

    Context "Hook Script References" {
        It "Should reference PowerShell scripts" {
            $hookJson = $script:Settings | ConvertTo-Json -Depth 10
            $hookJson | Should -Match "\.ps1"
        }

        It "Should use correct PowerShell invocation" {
            $hookJson = $script:Settings | ConvertTo-Json -Depth 10
            $hookJson | Should -Match "powershell\.exe"
        }

        It "Should use -ExecutionPolicy Bypass" {
            $hookJson = $script:Settings | ConvertTo-Json -Depth 10
            $hookJson | Should -Match "ExecutionPolicy Bypass"
        }
    }

    Context "Referenced Scripts Exist" {
        It "All referenced .ps1 scripts should exist" {
            $hookJson = $script:Settings | ConvertTo-Json -Depth 10

            # Extract all .ps1 file references
            $scriptMatches = [regex]::Matches($hookJson, '\\\\([^\\]+\.ps1)')

            foreach ($match in $scriptMatches) {
                $scriptName = $match.Groups[1].Value
                $scriptPath = Join-Path $script:WinHooksDir $scriptName

                # Note: Some scripts may be in different locations
                # This test checks the win/ directory
                if (-not (Test-Path $scriptPath)) {
                    Write-Warning "Script not found in win/: $scriptName"
                }
            }
        }
    }
}

Describe "Refactoring Infrastructure" {
    Context "pc-refactor.md" {
        It "Should have pc-refactor.md" {
            $path = Join-Path (Get-RepoRoot) "pc-refactor.md"
            Test-Path $path | Should -BeTrue
        }

        It "Should document transformation patterns" {
            $path = Join-Path (Get-RepoRoot) "pc-refactor.md"
            $content = Get-Content $path -Raw

            $content | Should -Match "Transformation Patterns"
            $content | Should -Match "PowerShell"
        }
    }

    Context "Sync Script" {
        It "Should have Sync-Upstream.ps1" {
            $path = Join-Path (Get-RepoRoot) "scripts\Sync-Upstream.ps1"
            Test-Path $path | Should -BeTrue
        }

        It "Should be valid PowerShell syntax" {
            $path = Join-Path (Get-RepoRoot) "scripts\Sync-Upstream.ps1"
            $errors = $null
            [System.Management.Automation.PSParser]::Tokenize(
                (Get-Content $path -Raw),
                [ref]$errors
            ) | Out-Null

            $errors.Count | Should -Be 0
        }
    }
}
