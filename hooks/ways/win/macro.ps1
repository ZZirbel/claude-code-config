#Requires -Version 5.1
# Core macro - generates the available ways table for session start.
# This is the archetype macro: other macros follow this pattern.
#
# A macro is a shell script referenced by a way's `macro: prepend` field.
# Its stdout is prepended to the way content before injection.
# Keep macros fast (no network, no heavy computation).

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$waysDir = Join-Path $env:USERPROFILE ".claude\hooks\ways"

# -- Skills context cost --
$skillCount = 0
if (Get-Command claude -ErrorAction SilentlyContinue) {
    try {
        $skillCount = (claude plugin list 2>$null | Select-String '✔ enabled').Count
    } catch {
        $skillCount = 0
    }
}

if ($skillCount -gt 12) {
    Write-Output "Skills loaded: $skillCount - **HIGH context cost.** Tell the user: `"You have $skillCount skills loaded. Each adds instructions to early context, degrading response quality. Run ``claude plugin list`` and disable unused ones. Aim for <=5.`""
    Write-Output ""
} elseif ($skillCount -gt 5) {
    Write-Output "Skills loaded: $skillCount - moderate context cost. Suggest reviewing with ``claude plugin list``."
    Write-Output ""
}

# -- Available ways table --
Write-Output "## Available Ways"
Write-Output ""

$currentDomain = ""

# Find all way .md files in subdirectories
$wayFiles = Get-ChildItem -Path $waysDir -Recurse -Filter "*.md" -File -ErrorAction SilentlyContinue |
    Where-Object {
        $rel = $_.FullName.Substring($waysDir.Length + 1) -replace '\\', '/'
        ($rel -match '.+/.+') -and ($_.Name -notmatch '\.check\.md$')
    } | Sort-Object FullName

foreach ($wayFile in $wayFiles) {
    $relpath = $wayFile.DirectoryName.Substring($waysDir.Length + 1) -replace '\\', '/'

    # Skip files not in a domain/way subdirectory
    if ($relpath -notmatch '/') { continue }

    $domain = ($relpath -split '/')[0]
    $wayname = ($relpath -split '/', 2)[1] -replace '/', ' > '

    # Domain header
    if ($domain -ne $currentDomain) {
        $domainDisplay = $domain.Substring(0,1).ToUpper() + $domain.Substring(1)
        Write-Output "### $domainDisplay"
        Write-Output ""
        Write-Output "| Way | Tool Trigger | Keyword Trigger |"
        Write-Output "|-----|--------------|-----------------|"
        $currentDomain = $domain
    }

    # Parse frontmatter (first YAML block only)
    $content = Get-Content $wayFile.FullName -Raw
    $frontmatter = ""
    if ($content -match '(?ms)^---\r?\n(.+?)\r?\n---') {
        $frontmatter = $Matches[1]
    } else {
        continue
    }

    function Get-FmField($fieldName) {
        if ($frontmatter -match "(?m)^${fieldName}:\s*(.+)$") {
            return $Matches[1].Trim()
        }
        return $null
    }

    $matchType = Get-FmField "match"
    $pattern = Get-FmField "pattern"
    $commands = Get-FmField "commands"
    $files = Get-FmField "files"

    # Tool trigger column
    $toolTrigger = "---"
    if ($commands) {
        $cmdClean = $commands -replace '\\', ''
        if ($cmdClean -match 'git commit') { $toolTrigger = 'Run ``git commit``' }
        elseif ($cmdClean -match '\^gh|gh ') { $toolTrigger = 'Run ``gh``' }
        elseif ($cmdClean -match 'ssh|scp|rsync') { $toolTrigger = 'Run ``ssh``' }
        elseif ($cmdClean -match 'pytest|jest') { $toolTrigger = 'Run test runner' }
        elseif ($cmdClean -match 'npm install|pip install') { $toolTrigger = 'Run package install' }
        elseif ($cmdClean -match 'git apply') { $toolTrigger = 'Run ``git apply``' }
        else { $toolTrigger = 'Run command' }
    } elseif ($files) {
        if ($files -match 'docs/adr') { $toolTrigger = 'Edit ``docs/adr/*.md``' }
        elseif ($files -match '\.env') { $toolTrigger = 'Edit ``.env``' }
        elseif ($files -match '\.patch') { $toolTrigger = 'Edit ``*.patch``' }
        elseif ($files -match 'todo-') { $toolTrigger = 'Edit ``.claude/todo-*.md``' }
        elseif ($files -match 'ways/') { $toolTrigger = 'Edit ``.claude/ways/*.md``' }
        elseif ($files -match 'README') { $toolTrigger = 'Edit ``README.md``' }
        else { $toolTrigger = 'Edit files' }
    }

    # Keyword trigger column
    $keywordDisplay = "---"
    if ($matchType -eq "semantic" -or $matchType -eq "model") {
        $keywordDisplay = "_($matchType)_"
    } elseif ($pattern) {
        # Strip regex syntax to show human-readable keywords
        $kw = $pattern -replace '[.][?+*]', ' '
        $kw = $kw -replace '\\[bnrst]', ''
        $kw = $kw -replace '\\', ''
        $kw = $kw -replace '[?^$]', ''
        $kw = $kw -replace '[()]', ' '
        $kw = $kw -replace '\|', ', '
        $kw = $kw -replace '[\[\]]', ''
        $kw = $kw -replace '\s+', ' '
        $kw = $kw -replace '\s*,\s*', ','
        $kw = $kw -replace ',+', ','
        $kw = $kw.Trim(',').Trim()
        $kw = $kw -replace ',', ', '
        $keywordDisplay = $kw
    }

    Write-Output "| **$wayname** | $toolTrigger | $keywordDisplay |"
}

Write-Output ""
Write-Output 'Project-local ways: `$PROJECT/.claude/ways/{domain}/{way}/{way}.md` override global.'

# -- AGENTS.md migration notice --
$projectDirEnv = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $PWD.Path }

if ($projectDirEnv -and $projectDirEnv -ne $env:USERPROFILE -and (Test-Path $projectDirEnv -PathType Container)) {
    $noMigration = Join-Path $projectDirEnv ".claude\no-agents-migration"
    if (-not (Test-Path $noMigration)) {
        $agentsFiles = Get-ChildItem -Path $projectDirEnv -Filter "AGENTS.md" -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Sort-Object FullName

        if ($agentsFiles.Count -gt 0) {
            Write-Output ""
            Write-Output "## AGENTS.md Detected"
            Write-Output ""
            Write-Output "Found $($agentsFiles.Count) AGENTS.md file(s):"
            Write-Output ""
            foreach ($f in $agentsFiles) {
                $relPath = $f.FullName.Substring($projectDirEnv.Length + 1)
                $lineCount = (Get-Content $f.FullName).Count
                Write-Output "- ``$relPath`` ($lineCount lines)"
            }
            Write-Output ""
            Write-Output "**Ways are already active** - this table was generated by the framework."
            Write-Output "AGENTS.md front-loads all instructions into context at once, which degrades"
            Write-Output "performance as context grows. Ways fire once per session, only when relevant."
            Write-Output ""
            Write-Output "**Read the AGENTS.md file(s) above**, then ask the user:"
            Write-Output "1. **Migrate** - decompose into project-scoped ways (``.claude/ways/``)"
            Write-Output "2. **Keep** - leave untouched (may duplicate/conflict with ways)"
            Write-Output "3. **Decline** - create ``.claude/no-agents-migration`` to suppress this notice"
        }
    }
}
