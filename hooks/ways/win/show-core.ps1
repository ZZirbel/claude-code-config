# Show core.md with dynamic table from macro
# Runs macro.ps1 first, then outputs static content from core.md
#
# Creates a core marker so check-state.ps1 can detect if core guidance
# was lost (e.g., plan mode context clear) and re-inject it.

param()

# Read JSON from stdin
$inputJson = $input | Out-String
try {
    $data = $inputJson | ConvertFrom-Json
    $sessionId = $data.session_id
} catch {
    $sessionId = ""
}

$waysDir = Join-Path $env:USERPROFILE ".claude\hooks\ways"
$winDir = Join-Path $waysDir "win"
$claudeDir = Join-Path $env:USERPROFILE ".claude"

# Run macro to generate dynamic table
$macroScript = Join-Path $winDir "macro.ps1"
if (Test-Path $macroScript) {
    & $macroScript
}

# Output static content (skip frontmatter)
$coreFile = Join-Path $waysDir "core.md"
if (Test-Path $coreFile) {
    $content = Get-Content $coreFile -Raw
    $lines = $content -split "`n"
    $output = @()
    $fmCount = 0

    foreach ($line in $lines) {
        if ($line -match '^---\s*$') {
            $fmCount++
            continue
        }
        if ($fmCount -ne 1) {
            $output += $line
        }
    }

    $output -join "`n"
}

# Append ways version: tag (if any) + commit + clean/dirty state
try {
    Push-Location $claudeDir
    $waysVersion = git describe --tags --always --dirty 2>$null
    if (-not $waysVersion) { $waysVersion = "unknown" }
    Pop-Location
} catch {
    $waysVersion = "unknown"
}

Write-Output ""
Write-Output "---"
Write-Output "_Ways version: $waysVersion_"

# If dirty, enumerate what's changed
if ($waysVersion -match "-dirty$") {
    try {
        Push-Location $claudeDir
        $dirtyFiles = git status --short 2>$null | ForEach-Object { ($_ -split '\s+', 2)[1] }
        $dirtyCount = ($dirtyFiles | Measure-Object).Count
        $maxShow = 5
        Pop-Location

        Write-Output ""
        $plural = if ($dirtyCount -ne 1) { "s" } else { "" }
        Write-Output "_Uncommitted changes ($dirtyCount file$plural):_"

        # Show first N files (sorted by modification time would require more code)
        $shown = 0
        foreach ($f in $dirtyFiles) {
            if ($shown -ge $maxShow) { break }
            Write-Output "_  $f_"
            $shown++
        }

        if ($dirtyCount -gt $maxShow) {
            $remaining = $dirtyCount - $maxShow
            Write-Output "_  ... and $remaining more_"
        }
        Write-Output "_Run ``git -C ~/.claude status --short`` to list all._"
    } catch {}
}

# Mark core as injected for this session
if ($sessionId) {
    $timestamp = [int][double]::Parse((Get-Date -UFormat %s))
    $markerPath = Join-Path $env:TEMP ".claude-core-$sessionId"
    Set-Content -Path $markerPath -Value $timestamp -NoNewline
}
