#Requires -Version 5.1
# Per-user sessions root — shared by all hook scripts.
# Must agree with session::sessions_root() in the ways binary.
#
# Usage: . "$PSScriptRoot\sessions-root.ps1"
#   then use $script:SESSIONS_ROOT

$script:SESSIONS_ROOT = Join-Path $env:TEMP ".claude-sessions-$([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)"
