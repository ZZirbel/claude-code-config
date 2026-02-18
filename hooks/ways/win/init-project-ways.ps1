# SessionStart: Initialize project .claude/ directory structure
# Creates ways template and .gitignore so ways get committed
# but developer-local files stay out of version control.

param()

$projectDir = if ($env:CLAUDE_PROJECT_DIR) { $env:CLAUDE_PROJECT_DIR } else { $PWD.Path }
$claudeDir = Join-Path $projectDir ".claude"
$waysDir = Join-Path $claudeDir "ways"
$template = Join-Path $waysDir "_template.md"
$gitignore = Join-Path $claudeDir ".gitignore"

# Only create if .claude exists (respect projects that don't use it)
# Or create both if this looks like a git repo
$gitDir = Join-Path $projectDir ".git"
if ((Test-Path $claudeDir) -or (Test-Path $gitDir)) {
    if (-not (Test-Path $waysDir)) {
        New-Item -ItemType Directory -Path $waysDir -Force | Out-Null
    }

    # Ensure .gitignore exists - commit ways, ignore local state
    if (-not (Test-Path $gitignore)) {
        $gitignoreContent = @"
# Developer-local files (not committed)
settings.local.json
todo-*.md
memory/
projects/
plans/

# Ways and CLAUDE.md ARE committed (shared team knowledge)
"@
        Set-Content -Path $gitignore -Value $gitignoreContent -Encoding UTF8
        Write-Output "Created .claude/.gitignore"
    }

    if (-not (Test-Path $template)) {
        $templateContent = @"
# Project Ways Template

Ways are contextual guidance that loads once per session when triggered.
Each way lives in its own directory: ``{domain}/{wayname}/way.md``

## Creating a Way

1. Create a directory: ``.claude/ways/{domain}/{wayname}/``
2. Add ``way.md`` with YAML frontmatter + guidance

### Pattern matching (for known keywords):

``````yaml
---
pattern: component|hook|useState|useEffect
files: \.(jsx|tsx)$
commands: npm\ run\ build
---
# React Way
- Use functional components with hooks
``````

### Semantic matching (for broad concepts):

``````yaml
---
description: React component design, hooks, state management
vocabulary: component hook useState useEffect jsx props render state
threshold: 2.0
---
# React Way
- Use functional components with hooks
``````

Matching is additive - a way can have both pattern and semantic triggers.

## Tips

- Keep guidance compact and actionable
- Include the *why* - agents apply better judgment when they understand the reason
- Use ``/ways-tests score <way> "sample prompt"`` to verify matching
- Use ``/ways-tests suggest <way>`` to find vocabulary gaps
"@
        Set-Content -Path $template -Value $templateContent -Encoding UTF8
        Write-Output "Created project ways template: $template"
    }
}
