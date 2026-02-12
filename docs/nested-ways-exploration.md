# Nested Ways: Exploration Notes

## Current Structure

Ways are organized as `{domain}/{wayname}/way.md` — exactly two levels deep.

```
hooks/ways/
├── softwaredev/          # domain
│   ├── commits/way.md    # way
│   ├── github/way.md
│   └── testing/way.md
├── meta/
│   ├── knowledge/way.md
│   └── skills/way.md
└── itops/
    └── incident/way.md
```

### What enforces two levels

| Component | Assumption | Code |
|-----------|-----------|------|
| `macro.sh` | `domain="${relpath%%/*}"`, `wayname="${relpath##*/}"` — first and last path segments only | Line 23-24 |
| `macro.sh` | `[[ "$relpath" != */* ]] && continue` — skips anything without exactly one `/` | Line 20 |
| `show-way.sh` | Takes a way path like `softwaredev/github`, markers use `tr '/' '-'` | Line 45 |
| `check-prompt.sh` | `find -name "way.md"` — already recursive, no depth limit | Line 85 |
| `check-bash-pre.sh` | Same `find` pattern — recursive | Line 58 |
| Markers | `/tmp/.claude-way-{path-with-dashes}-{session}` — works at any depth | Line 70 |

### Key finding

The discovery scripts (`check-prompt.sh`, `check-bash-pre.sh`, `check-file-pre.sh`, `check-state.sh`) already use recursive `find`. They would discover `softwaredev/commits/conventional/way.md` today. **The constraint is in `macro.sh` (table generation) and the mental model, not the matching engine.**

## What Nested Ways Would Look Like

```
hooks/ways/
├── meta/
│   └── knowledge/
│       ├── way.md              # Light: "what are ways" — fires on keyword "way"
│       └── authoring/
│           └── way.md          # Heavy: format spec, fields — fires on file edit
├── softwaredev/
│   └── commits/
│       ├── way.md              # Core: conventional format, rules
│       └── scoping/
│           └── way.md          # Detail: how to pick good scopes
└── itops/
    └── incident/
        ├── way.md              # Overview: triage flow
        ├── l0/way.md           # Detail: L0 runbook
        └── l1/way.md           # Detail: L1 escalation
```

The path becomes the taxonomy: `meta/knowledge/authoring` is naturally a child of `meta/knowledge`.

## What Would Need to Change

### Already works (no changes needed)
- **Discovery**: all `find -name "way.md"` calls are recursive
- **Matching**: frontmatter patterns work regardless of depth
- **Markers**: `tr '/' '-'` handles any path depth
- **show-way.sh**: takes arbitrary path, resolves to file, no depth assumption

### Needs modification

**`macro.sh` table generation** (the only hard constraint):
- Currently extracts domain as first segment, wayname as last segment
- Nested ways would need: domain as first segment, wayname as full sub-path
- The table could indent nested ways or show them as `parent/child`

```bash
# Current (two-level only)
domain="${relpath%%/*}"    # "softwaredev"
wayname="${relpath##*/}"   # "commits"

# Nested (n-level)
domain="${relpath%%/*}"           # "softwaredev"
wayname="${relpath#*/}"           # "commits/scoping" or "commits"
display_name="${wayname//\// > }" # "commits > scoping"
```

**Table display** — how to show hierarchy:

Option A: Flat with breadcrumbs
```
| knowledge          | ... | way, ways |
| knowledge > author | ... | _(file edit)_ |
```

Option B: Indentation
```
| knowledge          | ... | way, ways |
|   authoring        | ... | _(file edit)_ |
```

Option C: Only show leaf ways, skip parents that have children (parent becomes a category, not an injection)

### Design considerations

1. **Parent + child or parent-only?** If `meta/knowledge/way.md` exists and `meta/knowledge/authoring/way.md` also exists, both can fire independently. The parent fires on "way" keyword, the child fires on file edit. They're independent triggers with independent markers. This is already how it works — it's just that nobody has put a `way.md` at both levels yet.

2. **Marker dedup across depth** — currently `meta-knowledge` and `meta-knowledge-authoring` are different markers. A child firing doesn't suppress the parent. This seems correct: they're different concerns at different granularities.

3. **Project-local override semantics** — currently project-local wins over global for the same path. With nesting, a project could override `softwaredev/commits/way.md` without overriding `softwaredev/commits/scoping/way.md`. The path-based resolution already handles this.

4. **Table size** — nesting could proliferate ways. The table is already 28 rows. Need a convention for when to nest vs when to keep flat. Suggestion: nest when a way has clearly separable concerns at different trigger granularities (knowledge: using vs authoring). Don't nest just for taxonomy.

## What We Get

```
(parent)-[:CONTAINS]->(child)  // structural
(parent)-[:TRIGGER {broad}]->(injection)
(child)-[:TRIGGER {narrow}]->(injection)  // independent, more specific
```

- **Progressive disclosure**: broad trigger fires the overview, narrow trigger fires the detail
- **Token efficiency**: you only get the heavy reference when you're actually doing the narrow task
- **Natural taxonomy**: the filesystem IS the hierarchy, no metadata needed
- **Backward compatible**: existing two-level ways keep working, nesting is additive

## Recommendation

This is low-effort to support. The matching engine already handles it. The only real work is updating `macro.sh` to display nested ways properly in the table, and deciding on the display convention. A proof-of-concept with `meta/knowledge/authoring/way.md` would validate the approach with minimal risk.
