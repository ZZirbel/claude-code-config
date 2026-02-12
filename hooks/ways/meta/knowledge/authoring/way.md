---
match: regex
files: \.claude/ways/.*way\.md$
scope: agent, subagent
provenance:
  policy:
    - uri: docs/hooks-and-ways/extending.md
      type: governance-doc
  controls:
    - id: ISO 9001:2015 7.5 (Documented Information)
      justifications:
        - Way file format specification ensures documented information is appropriate and suitable
        - Frontmatter schema (match, pattern, files, commands) standardizes trigger documentation
        - Writing voice guidance ensures guidance is readable by context-free readers
  verified: 2026-02-05
  rationale: >
    Format spec and authoring guidance for writing effective ways.
    Only injected when editing way files — heavier reference that
    isn't needed for general "ways" conversations.
---
# Authoring Ways

## Way File Format

Each way lives in `{domain}/{wayname}/way.md` with YAML frontmatter:

```markdown
---
match: regex              # or "semantic"
pattern: foo|bar|regex.*  # for regex matching
files: \.md$|docs/.*
commands: git\ commit
macro: prepend
---
# Way Name

## Guidance
- Compact, actionable points
```

For semantic matching:
```markdown
---
match: semantic
description: reference text for similarity
vocabulary: domain specific words
threshold: 0.55           # optional, default 0.58
---
```

For model-based classification (uses Haiku):
```markdown
---
match: model
description: security-sensitive operations, auth changes, credential handling
---
```

For state-based triggers:
```markdown
---
trigger: context-threshold
threshold: 90             # percentage (0-100)
---
```

### Frontmatter Fields

**Pattern-based:**
- `match:` - `regex` (default), `semantic`, or `model`
- `pattern:` - Regex matched against user prompts
- `files:` - Regex matched against file paths (Edit/Write)
- `commands:` - Regex matched against bash commands

**Semantic (NCD):**
- `description:` - Reference text for semantic similarity
- `vocabulary:` - Domain words for keyword counting
- `threshold:` - NCD threshold (lower = stricter, default 0.58)

**Model (Haiku):**
- `description:` - What this way covers (Haiku classifies yes/no)
- Adds ~800ms latency but high accuracy

**State-based:**
- `trigger:` - State condition type (`context-threshold`, `file-exists`, `session-start`)
- `threshold:` - For context-threshold: percentage (0-100)
- `path:` - For file-exists: glob pattern relative to project

**Other:**
- `macro:` - `prepend` or `append` to run `macro.sh`

## Creating a New Way

1. Create directory in:
   - Global: `~/.claude/hooks/ways/{domain}/{wayname}/`
   - Project: `$PROJECT/.claude/ways/{domain}/{wayname}/`

2. Add `way.md` with frontmatter + guidance

3. Optionally add `macro.sh` for dynamic context

**That's it.** No config files to update. Project ways override global ways with the same path. Ways can nest arbitrarily: `{domain}/{parent}/{child}/way.md`.

## Writing Ways Well

Write as a collaborator, not an authority. Include the *why* — an agent that understands the reason applies better judgment at the edges. Write for a reader with no prior context.

For state transitions and process flows, prefer Cypher-style notation over ASCII diagrams — it's compact, the model parses it natively, and it saves tokens:
```
(state_a)-[:EVENT {context}]->(state_b)  // what happens
```

Full authoring guide: `docs/hooks-and-ways/extending.md`
