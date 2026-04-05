//! Initialize project .claude/ways/ structure.
//! Replaces init-project-ways.sh (81 lines).

use anyhow::Result;
use std::path::PathBuf;

const GITIGNORE_CONTENT: &str = "\
# Developer-local files (not committed)
settings.local.json
todo-*.md
memory/
projects/
plans/

# Ways and CLAUDE.md ARE committed (shared team knowledge)
";

const TEMPLATE_CONTENT: &str = "\
# Project Ways Template

Ways are contextual guidance that loads once per session when triggered.
Each way lives in its own directory: `{domain}/{wayname}/{wayname}.md`

## Creating a Way

1. Create a directory: `.claude/ways/{domain}/{wayname}/`
2. Add `{wayname}.md` with YAML frontmatter + guidance

### Pattern matching (for known keywords):

```yaml
---
pattern: component|hook|useState|useEffect
files: \\.(jsx|tsx)$
commands: npm\\ run\\ build
---
# React Way
- Use functional components with hooks
```

### Semantic matching (for broad concepts):

```yaml
---
description: React component design, hooks, state management
vocabulary: component hook useState useEffect jsx props render state
threshold: 2.0
---
# React Way
- Use functional components with hooks
```

Matching is additive — a way can have both pattern and semantic triggers.

## Tips

- Keep guidance compact and actionable
- Include the *why* — agents apply better judgment when they understand the reason
- Use `ways suggest <file>` to find vocabulary gaps
";

pub fn run(project: Option<&str>) -> Result<()> {
    let project_dir = project
        .map(|s| s.to_string())
        .unwrap_or_else(|| {
            std::env::var("CLAUDE_PROJECT_DIR")
                .unwrap_or_else(|_| std::env::var("PWD").unwrap_or_else(|_| ".".to_string()))
        });

    let claude_dir = PathBuf::from(&project_dir).join(".claude");
    let ways_dir = claude_dir.join("ways");
    let gitignore = claude_dir.join(".gitignore");
    let template = ways_dir.join("_template.md");

    // Only create if .claude exists or this is a git repo
    let git_dir = PathBuf::from(&project_dir).join(".git");
    if !claude_dir.is_dir() && !git_dir.is_dir() {
        return Ok(());
    }

    if !ways_dir.is_dir() {
        std::fs::create_dir_all(&ways_dir)?;
    }

    if !gitignore.is_file() {
        std::fs::write(&gitignore, GITIGNORE_CONTENT)?;
        eprintln!("Created .claude/.gitignore");
    }

    if !template.is_file() {
        std::fs::write(&template, TEMPLATE_CONTENT)?;
        eprintln!("Created project ways template: {}", template.display());
    }

    Ok(())
}
