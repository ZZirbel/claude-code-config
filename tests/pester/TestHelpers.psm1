#Requires -Version 5.1
<#
.SYNOPSIS
    Helper functions for Pester tests

.DESCRIPTION
    Provides common utilities for testing claude-code-config hooks and functionality.
#>

# Get the root of the repository
$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:HooksDir = Join-Path $RepoRoot "hooks\ways"
$script:WinHooksDir = Join-Path $HooksDir "win"
$script:BinDir = Join-Path $RepoRoot "bin"

function Get-RepoRoot {
    return $script:RepoRoot
}

function Get-HooksDir {
    return $script:HooksDir
}

function Get-WinHooksDir {
    return $script:WinHooksDir
}

function Get-BinDir {
    return $script:BinDir
}

function Get-WayMatchBinary {
    <#
    .SYNOPSIS
        Returns the path to the way-match binary
    #>
    $binPath = Join-Path $script:BinDir "way-match"

    # On Windows, try with .exe extension first
    $exePath = "$binPath.exe"
    if (Test-Path $exePath) {
        return $exePath
    }

    # Try without extension (APE binary)
    if (Test-Path $binPath) {
        return $binPath
    }

    return $null
}

function Test-WayMatchBinary {
    <#
    .SYNOPSIS
        Tests if the way-match binary is available and functional
    #>
    $binary = Get-WayMatchBinary
    if (-not $binary) {
        return $false
    }

    try {
        $result = & $binary pair `
            --description "test description" `
            --vocabulary "test vocab" `
            --query "test query" `
            --threshold 0.1 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function New-MockHookInput {
    <#
    .SYNOPSIS
        Creates mock JSON input for hook testing

    .PARAMETER HookType
        Type of hook: SessionStart, UserPromptSubmit, PreToolUse, Stop, SubagentStart

    .PARAMETER Properties
        Additional properties to include
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('SessionStart', 'UserPromptSubmit', 'PreToolUse', 'Stop', 'SubagentStart')]
        [string]$HookType,

        [hashtable]$Properties = @{}
    )

    $baseInput = @{
        session_id = "test-session-$(Get-Random)"
        project_dir = $script:RepoRoot
        cwd = $script:RepoRoot
    }

    switch ($HookType) {
        'SessionStart' {
            $baseInput['type'] = 'startup'
        }
        'UserPromptSubmit' {
            $baseInput['prompt'] = $Properties['prompt'] ?? "test prompt"
        }
        'PreToolUse' {
            $baseInput['tool'] = @{
                name = $Properties['tool_name'] ?? "Bash"
                parameters = $Properties['parameters'] ?? @{}
            }
        }
        'Stop' {
            $baseInput['transcript'] = $Properties['transcript'] ?? @()
        }
        'SubagentStart' {
            $baseInput['agent_id'] = $Properties['agent_id'] ?? "subagent-$(Get-Random)"
        }
    }

    # Merge additional properties
    foreach ($key in $Properties.Keys) {
        if (-not $baseInput.ContainsKey($key)) {
            $baseInput[$key] = $Properties[$key]
        }
    }

    return $baseInput | ConvertTo-Json -Depth 10
}

function Invoke-HookScript {
    <#
    .SYNOPSIS
        Invokes a PowerShell hook script with mock input

    .PARAMETER ScriptName
        Name of the script (without .ps1 extension)

    .PARAMETER Input
        JSON string to pass as input
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScriptName,

        [Parameter(Mandatory)]
        [string]$Input
    )

    $scriptPath = Join-Path $script:WinHooksDir "$ScriptName.ps1"

    if (-not (Test-Path $scriptPath)) {
        throw "Hook script not found: $scriptPath"
    }

    # Invoke the script with input
    $result = $Input | & $scriptPath 2>&1

    return @{
        Output = $result
        ExitCode = $LASTEXITCODE
    }
}

function Get-WayFrontmatter {
    <#
    .SYNOPSIS
        Extracts a field from a way.md frontmatter

    .PARAMETER WayFile
        Path to the way.md file

    .PARAMETER Field
        Field name to extract
    #>
    param(
        [Parameter(Mandatory)]
        [string]$WayFile,

        [Parameter(Mandatory)]
        [string]$Field
    )

    if (-not (Test-Path $WayFile)) {
        return $null
    }

    $content = Get-Content $WayFile -Raw

    # Match YAML frontmatter
    if ($content -match "(?ms)^---\r?\n(.+?)\r?\n---") {
        $yaml = $Matches[1]

        # Extract field value
        if ($yaml -match "(?m)^${Field}:\s*(.+)$") {
            $value = $Matches[1].Trim()
            # Remove quotes if present
            $value = $value.Trim('"').Trim("'")
            return $value
        }
    }

    return $null
}

function Get-AllWayFiles {
    <#
    .SYNOPSIS
        Returns all way.md files in the hooks/ways directory
    #>
    return Get-ChildItem -Path $script:HooksDir -Filter "way.md" -Recurse |
        Where-Object { $_.FullName -notmatch "\\win\\" }
}

function New-TestMarkerDir {
    <#
    .SYNOPSIS
        Creates a temporary directory for test markers

    .OUTPUTS
        Path to the temp directory
    #>
    $tempDir = Join-Path $env:TEMP "claude-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    return $tempDir
}

function Remove-TestMarkerDir {
    <#
    .SYNOPSIS
        Removes a test marker directory

    .PARAMETER Path
        Path to remove
    #>
    param([string]$Path)

    if ($Path -and (Test-Path $Path) -and $Path -match "claude-test-") {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-RepoRoot'
    'Get-HooksDir'
    'Get-WinHooksDir'
    'Get-BinDir'
    'Get-WayMatchBinary'
    'Test-WayMatchBinary'
    'New-MockHookInput'
    'Invoke-HookScript'
    'Get-WayFrontmatter'
    'Get-AllWayFiles'
    'New-TestMarkerDir'
    'Remove-TestMarkerDir'
)
