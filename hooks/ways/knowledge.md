---
keywords: knowledge|ways|guidance|context.?inject|how.?do.?ways
files: \.claude/ways/.*\.md$
---
# Knowledge Way

## How Ways Work
Ways are contextual guidance that loads once per session when triggered by:
- **Keywords** in user prompts (UserPromptSubmit)
- **Tool use** - commands, file paths, descriptions (PostToolUse)

## Way File Format

Each way is a self-contained markdown file with YAML frontmatter:

```markdown
---
keywords: pattern1|pattern2|regex.*
files: \.md$|docs/.*
commands: git\ commit|npm\ test
---
# Way Name

## Guidance content here
- Compact, actionable points
- Not exhaustive documentation
```

### Frontmatter Fields
- `keywords:` - Regex patterns matched against user prompts and tool descriptions
- `files:` - Regex patterns matched against file paths (Edit/Write)
- `commands:` - Regex patterns matched against bash commands

## Creating a New Way

1. Create `wayname.md` in:
   - Global: `~/.claude/hooks/ways/`
   - Project: `$PROJECT/.claude/ways/`

2. Add frontmatter with triggers

3. Write compact guidance

**That's it.** No config files to update.

## Project-Local Ways

Projects can override or add ways:
```
$PROJECT/.claude/
└── ways/
    ├── our-api.md       # Project conventions
    ├── deployment.md    # How we deploy
    └── testing.md       # Override global testing way
```

Project ways take precedence over global ways with same name.

## Locations
- Global: `~/.claude/hooks/ways/`
- Project: `$PROJECT/.claude/ways/`
- Markers: `/tmp/.claude-way-{name}-{session_id}`
