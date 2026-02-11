---
match: regex
pattern: \bway\b|\bways\b|knowledge|guidance|context.?inject
files: \.claude/ways/.*way\.md$
scope: agent, subagent
provenance:
  policy:
    - uri: docs/hooks-and-ways/extending.md
      type: governance-doc
    - uri: docs/hooks-and-ways/rationale.md
      type: governance-doc
  controls:
    - id: ISO 9001:2015 7.5 (Documented Information)
      justifications:
        - Way file format specification ensures documented information is appropriate and suitable
        - Frontmatter schema (match, pattern, files, commands) standardizes trigger documentation
        - Writing voice guidance ensures guidance is readable by context-free readers
    - id: ISO/IEC 27001:2022 5.2 (Policy)
      justifications:
        - Collaborative framing pattern ensures policies are communicated, not just asserted
        - Domain organization (global vs project-local) establishes policy hierarchy
        - Enable/disable mechanism via ways.json provides controlled policy application
    - id: NIST SP 800-53 PL-2 (System Security and Privacy Plans)
      justifications:
        - Ways index at session start documents active security and privacy guidance
        - State machine ensures each policy is delivered exactly once per session
        - Project-local override mechanism allows plan tailoring per system
  verified: 2026-02-05
  rationale: >
    Guidance on writing effective ways implements ISO requirements for documented
    information to be appropriate and suitable for use. The collaborative framing
    pattern addresses ISO 27001 policy communication requirements — policies that
    explain reasoning get better adherence.
---
# Knowledge Way

## Ways vs Skills

**Skills** = semantically-discovered (Claude decides based on intent)
**Ways** = triggered (patterns, commands, file edits, or state conditions)

| Use Skills for | Use Ways for |
|---------------|--------------|
| Semantic discovery ("explain code") | Tool-triggered (`git commit` → format reminder) |
| Tool restrictions (`allowed-tools`) | File-triggered (edit `.env` → config guidance) |
| Multi-file reference docs | Session-gated (once per session) |
| | Dynamic context (macro queries API) |

They complement: Skills can't detect tool execution. Ways support both regex and semantic matching.

## How Ways Work
Ways are contextual guidance that loads once per session when triggered by:
- **Keywords** in user prompts (UserPromptSubmit)
- **Tool use** - commands, file paths (PreToolUse)
- **State conditions** - context threshold, file existence (UserPromptSubmit)

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

**That's it.** No config files to update. Project ways override global ways with the same path.

## Locations
- Global: `~/.claude/hooks/ways/{domain}/{wayname}/way.md`
- Project: `$PROJECT/.claude/ways/{domain}/{wayname}/way.md`
- Disable domains: `~/.claude/ways.json` → `{"disabled": ["domain"]}`

## State Machine

```
(not_shown)-[:TRIGGER {keyword|command|file|state}]->(shown)  // output + create marker
(shown)-[:TRIGGER]->(shown)  // no-op, idempotent
```

Each (way, session) pair has its own marker. Multiple ways can fire per prompt. Project-local wins over global for same name.

## Writing Ways Well

Write as a collaborator, not an authority. Include the *why* — an agent that understands the reason applies better judgment at the edges. Write for a reader with no prior context.

Full authoring guide: `docs/hooks-and-ways/extending.md`
