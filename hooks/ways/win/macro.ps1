# Dynamic table generator for core.md
# Scans all way.md files and generates a table of triggers

param()

$waysDir = Join-Path $env:USERPROFILE ".claude\hooks\ways"

Write-Output "## Available Ways"
Write-Output ""

# Track current domain for section headers
$currentDomain = ""

# Find all way.md files, sorted by path
$wayFiles = Get-ChildItem -Path $waysDir -Filter "way.md" -Recurse -File | Sort-Object FullName

foreach ($wayFile in $wayFiles) {
    # Extract relative path (e.g., "softwaredev\delivery\github")
    $relPath = $wayFile.FullName.Substring($waysDir.Length + 1)
    $relPath = $relPath -replace "\\way\.md$", ""
    $relPath = $relPath -replace "\\", "/"

    # Skip if not in a domain subdirectory
    if ($relPath -notmatch "/") { continue }

    # Extract domain (first segment) and way name (rest of path)
    $parts = $relPath -split "/", 2
    $domain = $parts[0]
    $subpath = if ($parts.Length -gt 1) { $parts[1] } else { "" }

    # Display nested ways with > breadcrumbs
    $wayname = $subpath -replace "/", " > "

    # Print domain header if changed
    if ($domain -ne $currentDomain) {
        $domainDisplay = $domain.Substring(0, 1).ToUpper() + $domain.Substring(1)
        Write-Output "### $domainDisplay"
        Write-Output ""
        Write-Output "| Way | Tool Trigger | Keyword Trigger |"
        Write-Output "|-----|--------------|-----------------|"
        $currentDomain = $domain
    }

    # Read way file and extract frontmatter
    $content = Get-Content $wayFile.FullName -Raw

    # Extract frontmatter fields
    $matchType = ""
    $pattern = ""
    $commands = ""
    $files = ""

    $lines = $content -split "`n"
    $inFrontmatter = $false

    foreach ($line in $lines) {
        if ($line -match '^---\s*$') {
            if (-not $inFrontmatter) {
                $inFrontmatter = $true
            } else {
                break
            }
            continue
        }
        if ($inFrontmatter) {
            if ($line -match '^match:\s*(.*)$') { $matchType = $Matches[1].Trim() }
            if ($line -match '^pattern:\s*(.*)$') { $pattern = $Matches[1].Trim() }
            if ($line -match '^commands:\s*(.*)$') { $commands = $Matches[1].Trim() }
            if ($line -match '^files:\s*(.*)$') { $files = $Matches[1].Trim() }
        }
    }

    # Build tool trigger description
    $toolTrigger = "---"
    if ($commands) {
        $cmdClean = $commands -replace "\\", ""
        switch -Regex ($cmdClean) {
            "git commit" { $toolTrigger = "Run ``git commit``" }
            "^gh|gh " { $toolTrigger = "Run ``gh``" }
            "ssh|scp|rsync" { $toolTrigger = "Run ``ssh``, ``scp``, ``rsync``" }
            "pytest|jest" { $toolTrigger = "Run ``pytest``, ``jest``, etc" }
            "npm install|pip install" { $toolTrigger = "Run ``npm install``, etc" }
            "git apply" { $toolTrigger = "Run ``git apply``" }
            default { $toolTrigger = "Run command" }
        }
    } elseif ($files) {
        switch -Regex ($files) {
            "docs/adr" { $toolTrigger = "Edit ``docs/adr/*.md``" }
            "\.env" { $toolTrigger = "Edit ``.env``" }
            "\.patch|\.diff" { $toolTrigger = "Edit ``*.patch``, ``*.diff``" }
            "todo-" { $toolTrigger = "Edit ``.claude/todo-*.md``" }
            "ways/" { $toolTrigger = "Edit ``.claude/ways/*.md``" }
            "README" { $toolTrigger = "Edit ``README.md``, ``docs/*.md``" }
            default { $toolTrigger = "Edit files matching pattern" }
        }
    }

    # Format pattern for display
    $keywordDisplay = "---"
    if ($matchType -eq "semantic" -or $matchType -eq "model") {
        $keywordDisplay = "_($matchType)_"
    } elseif ($pattern) {
        # Strip regex syntax, keep human-readable keywords
        $keywordDisplay = $pattern -replace '\.\?', ' ' -replace '\.\*', ' ' -replace '\.\+', ' '
        $keywordDisplay = $keywordDisplay -replace '\\b', '' -replace '\\', '' -replace '\?', ''
        $keywordDisplay = $keywordDisplay -replace '\^', '' -replace '\$', '' -replace '\(', ' '
        $keywordDisplay = $keywordDisplay -replace '\)', '' -replace '\|', ', ' -replace '\[', ''
        $keywordDisplay = $keywordDisplay -replace '\]', ''
        $keywordDisplay = $keywordDisplay -replace '\s+', ' ' -replace ',\s*,', ',' -replace '^,|,$', ''
        $keywordDisplay = $keywordDisplay.Trim()
    }

    Write-Output "| **$wayname** | $toolTrigger | $keywordDisplay |"
}

Write-Output ""
Write-Output "Project-local ways: ``\$PROJECT/.claude/ways/{domain}/{way}/way.md`` override global."
