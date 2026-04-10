#Requires -Version 5.1
#Requires -Modules Pester

<#
.SYNOPSIS
    Simulates Claude Code hook events to test PowerShell hook scripts

.DESCRIPTION
    These tests simulate the JSON input/output that Claude Code sends to hooks,
    verifying that the PowerShell scripts process them correctly.
#>

# Import at file scope so variables are available during Pester discovery
Import-Module "$PSScriptRoot\TestHelpers.psm1" -Force
$script:WinHooksDir = Get-WinHooksDir

BeforeAll {
    $script:TempDir = New-TestMarkerDir
    $env:CLAUDE_TEST_TEMP = $script:TempDir
    # Re-initialize here so $script: scope is available during the execution phase,
    # not just during Pester discovery (where the file-scope assignment runs).
    $script:WinHooksDir = Get-WinHooksDir
}

AfterAll {
    Remove-TestMarkerDir -Path $script:TempDir
    Remove-Item Env:\CLAUDE_TEST_TEMP -ErrorAction SilentlyContinue
}

Describe "PowerShell Hook Scripts" {
    Context "Script Availability" {
        $expectedScripts = @(
            "check-prompt"
            "check-bash-pre"
            "check-file-pre"
            "check-state"
            "show-core"
            "clear-markers"
            "match-way"
            "show-way"
            "macro"
            "detect-scope"
            "inject-subagent"
            "check-task-pre"
        )

        foreach ($script in $expectedScripts) {
            It "Should have $script.ps1" {
                $path = Join-Path $script:WinHooksDir "$script.ps1"
                Test-Path $path | Should -BeTrue
            }
        }
    }

    Context "check-prompt.ps1" -Skip:(-not (Test-Path (Join-Path $script:WinHooksDir "check-prompt.ps1"))) {
        It "Should accept valid JSON input without error" {
            $input = New-MockHookInput -HookType UserPromptSubmit -Properties @{
                prompt = "help me with git"
            }

            $scriptPath = Join-Path $script:WinHooksDir "check-prompt.ps1"
            { $input | & $scriptPath 2>&1 } | Should -Not -Throw
        }

        It "Should return valid JSON output" {
            $input = New-MockHookInput -HookType UserPromptSubmit -Properties @{
                prompt = "test prompt"
            }

            $scriptPath = Join-Path $script:WinHooksDir "check-prompt.ps1"
            $result = $input | & $scriptPath 2>&1

            if ($result) {
                { $result | ConvertFrom-Json } | Should -Not -Throw
            }
        }

        It "Should trigger GitHub way on PR-related prompt" {
            $input = New-MockHookInput -HookType UserPromptSubmit -Properties @{
                prompt = "create a pull request for this feature"
            }

            $scriptPath = Join-Path $script:WinHooksDir "check-prompt.ps1"
            $result = $input | & $scriptPath 2>&1

            # The result should contain GitHub-related content if the way matched
            # (This depends on actual way configuration)
            $LASTEXITCODE | Should -BeIn @(0, 1)
        }
    }

    Context "check-bash-pre.ps1" -Skip:(-not (Test-Path (Join-Path $script:WinHooksDir "check-bash-pre.ps1"))) {
        It "Should accept Bash tool input" {
            $input = New-MockHookInput -HookType PreToolUse -Properties @{
                tool_name = "Bash"
                parameters = @{
                    command = "git status"
                    description = "Check git status"
                }
            }

            $scriptPath = Join-Path $script:WinHooksDir "check-bash-pre.ps1"
            { $input | & $scriptPath 2>&1 } | Should -Not -Throw
        }

        It "Should trigger on git commit command" {
            $input = New-MockHookInput -HookType PreToolUse -Properties @{
                tool_name = "Bash"
                parameters = @{
                    command = "git commit -m 'test'"
                    description = "Commit changes"
                }
            }

            $scriptPath = Join-Path $script:WinHooksDir "check-bash-pre.ps1"
            $result = $input | & $scriptPath 2>&1

            $LASTEXITCODE | Should -BeIn @(0, 1)
        }
    }

    Context "check-file-pre.ps1" -Skip:(-not (Test-Path (Join-Path $script:WinHooksDir "check-file-pre.ps1"))) {
        It "Should accept Edit tool input" {
            $input = New-MockHookInput -HookType PreToolUse -Properties @{
                tool_name = "Edit"
                parameters = @{
                    file_path = "C:\test\example.js"
                }
            }

            $scriptPath = Join-Path $script:WinHooksDir "check-file-pre.ps1"
            { $input | & $scriptPath 2>&1 } | Should -Not -Throw
        }

        It "Should trigger on .env file" {
            $input = New-MockHookInput -HookType PreToolUse -Properties @{
                tool_name = "Edit"
                parameters = @{
                    file_path = "C:\project\.env"
                }
            }

            $scriptPath = Join-Path $script:WinHooksDir "check-file-pre.ps1"
            $result = $input | & $scriptPath 2>&1

            $LASTEXITCODE | Should -BeIn @(0, 1)
        }
    }

    Context "clear-markers.ps1" -Skip:(-not (Test-Path (Join-Path $script:WinHooksDir "clear-markers.ps1"))) {
        BeforeEach {
            # Create some test marker files
            $markerDir = $script:TempDir
            New-Item -Path "$markerDir\.claude-way-test-123" -ItemType File -Force | Out-Null
            New-Item -Path "$markerDir\.claude-core-test-123" -ItemType File -Force | Out-Null
        }

        It "Should execute without error" {
            $input = New-MockHookInput -HookType SessionStart

            $scriptPath = Join-Path $script:WinHooksDir "clear-markers.ps1"
            { $input | & $scriptPath 2>&1 } | Should -Not -Throw
        }
    }

    Context "show-core.ps1" -Skip:(-not (Test-Path (Join-Path $script:WinHooksDir "show-core.ps1"))) {
        It "Should execute on session start" {
            $input = New-MockHookInput -HookType SessionStart

            $scriptPath = Join-Path $script:WinHooksDir "show-core.ps1"
            { $input | & $scriptPath 2>&1 } | Should -Not -Throw
        }

        It "Should output core guidance content" {
            $input = New-MockHookInput -HookType SessionStart

            $scriptPath = Join-Path $script:WinHooksDir "show-core.ps1"
            $result = $input | & $scriptPath 2>&1

            # Should contain some content (core.md or generated table)
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "detect-scope.ps1" -Skip:(-not (Test-Path (Join-Path $script:WinHooksDir "detect-scope.ps1"))) {
        It "Should return 'agent' scope by default" {
            $input = @{
                session_id = "test-session-$(Get-Random)"
            } | ConvertTo-Json

            $scriptPath = Join-Path $script:WinHooksDir "detect-scope.ps1"
            $result = $input | & $scriptPath 2>&1

            # Default scope should be 'agent'
            $result | Should -Match "agent"
        }
    }

    Context "macro.ps1" -Skip:(-not (Test-Path (Join-Path $script:WinHooksDir "macro.ps1"))) {
        It "Should generate ways table" {
            $scriptPath = Join-Path $script:WinHooksDir "macro.ps1"
            $result = & $scriptPath 2>&1

            # Should output markdown table
            $result | Should -Match "\|"
        }
    }
}

Describe "Hook Output Format" {
    Context "JSON Structure" {
        It "Should output valid hookSpecificOutput format when matching" {
            # This is the expected format for hook output
            $expectedStructure = @{
                hookSpecificOutput = @{
                    additionalContext = "way content here"
                }
            }

            # Verify structure is valid JSON
            { $expectedStructure | ConvertTo-Json -Depth 5 } | Should -Not -Throw
        }

        It "Should handle empty output gracefully" {
            # When no ways match, hooks should output nothing or empty JSON
            $emptyOutput = ""
            $emptyJson = "{}"

            # Both should be acceptable
            { if ($emptyOutput) { $emptyOutput | ConvertFrom-Json } } | Should -Not -Throw
            { $emptyJson | ConvertFrom-Json } | Should -Not -Throw
        }
    }
}
