# Pester Tests for Windows PowerShell Hooks

This directory contains Pester tests for validating the Windows PowerShell hook implementations.

## Prerequisites

- PowerShell 5.1 or later
- Pester module v5.0 or later

### Installing Pester

```powershell
Install-Module Pester -Force -Scope CurrentUser -MinimumVersion 5.0
```

## Running Tests

### Run All Tests

```powershell
cd C:\Users\zanzi\GitHub\claude-code-config
Invoke-Pester -Path .\tests\pester -Output Detailed
```

### Run Specific Test File

```powershell
Invoke-Pester -Path .\tests\pester\Binary.Tests.ps1 -Output Detailed
```

### Run Tests with Code Coverage

```powershell
$config = New-PesterConfiguration
$config.Run.Path = ".\tests\pester"
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = ".\hooks\ways\win\*.ps1"
$config.Output.Verbosity = "Detailed"
Invoke-Pester -Configuration $config
```

### Generate Test Results XML (for CI)

```powershell
$config = New-PesterConfiguration
$config.Run.Path = ".\tests\pester"
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = ".\TestResults.xml"
$config.TestResult.OutputFormat = "NUnitXml"
Invoke-Pester -Configuration $config
```

## Test Files

| File | Description |
|------|-------------|
| `TestHelpers.psm1` | Shared helper functions and utilities |
| `Binary.Tests.ps1` | Tests for the way-match BM25 binary |
| `HookSimulation.Tests.ps1` | Simulates Claude Code hook events |
| `Integration.Tests.ps1` | Full pipeline integration tests |
| `Parity.Tests.ps1` | Compares Bash vs PowerShell output (requires Git Bash) |

## Test Categories

### Binary Tests
Verifies the `way-match` APE binary works on Windows:
- Binary availability and execution
- BM25 matching accuracy
- Edge case handling (empty input, special characters, Unicode)

### Hook Simulation Tests
Simulates the JSON input/output that Claude Code sends to hooks:
- Script availability
- Valid JSON processing
- Expected trigger behavior

### Integration Tests
Tests the complete system configuration:
- Way file structure and frontmatter parsing
- Domain organization
- Configuration file validity
- Settings.windows.json hook definitions

### Parity Tests
Compares PowerShell and Bash implementations (requires bash):
- Output format compatibility
- Frontmatter parsing consistency
- Environment variable handling

## Writing New Tests

When adding new tests, follow this pattern:

```powershell
#Requires -Version 5.1
#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot\TestHelpers.psm1" -Force
}

Describe "Feature Name" {
    Context "Specific Scenario" {
        It "Should do expected thing" {
            # Arrange
            $input = "test data"

            # Act
            $result = Some-Function $input

            # Assert
            $result | Should -Be "expected"
        }
    }
}
```

## Troubleshooting

### "Pester module not found"
```powershell
Install-Module Pester -Force -Scope CurrentUser
```

### "Execution policy prevents running scripts"
```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### "way-match binary not found"
The APE binary should be at `bin/way-match`. On Windows, it may need to be renamed to `way-match.exe` or run through a compatibility layer.

### "Bash not available" (Parity tests skipped)
Install Git for Windows, which includes Git Bash:
https://git-scm.com/download/win
