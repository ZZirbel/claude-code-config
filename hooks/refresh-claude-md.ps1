# Refresh CLAUDE.md context after compaction
# This script ensures Claude re-reads both user and project scope configurations

Write-Host "Refreshing CLAUDE.md context post-compaction..."

# Force re-read of user scope CLAUDE.md
$ClaudeMdPath = "$env:USERPROFILE\.claude\CLAUDE.md"
if (Test-Path $ClaudeMdPath) {
    (Get-Item $ClaudeMdPath).LastWriteTime = Get-Date
    Write-Host "User scope CLAUDE.md refreshed"
}

# Hint: Project-scoped CLAUDE.md files should be discovered and read as needed
Write-Host "Project scope CLAUDE.md discovery will be handled by updated instructions"

Write-Host "Context refresh complete - Claude will re-read configurations on next interaction"
exit 0
