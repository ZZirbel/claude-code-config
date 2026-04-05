#Requires -Version 5.1
# Guard: exit silently if ways binary is not available.
# Source this at the top of any hook script that calls the ways binary.
#
# Usage: . "$PSScriptRoot\require-ways.ps1"
#
# If the binary is missing, the script exits 0 (no error, no output).
# The SessionStart check-setup.ps1 hook handles the user-facing diagnostic.

$script:WAYS_BIN = Join-Path $env:USERPROFILE ".claude\bin\ways.exe"
if (-not (Test-Path $script:WAYS_BIN)) {
    # Also check without .exe extension (cross-platform binary)
    $script:WAYS_BIN = Join-Path $env:USERPROFILE ".claude\bin\ways"
    if (-not (Test-Path $script:WAYS_BIN)) {
        exit 0
    }
}
