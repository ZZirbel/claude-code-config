---
status: Draft
date: 2026-03-23
deciders:
  - aaronsb
  - claude
related:
  - ADR-108
  - ADR-107
  - ADR-105
---

# ADR-109: Project-Scope Way Embedding with Manifest-Based Staleness Detection

## Context

ADR-108 shipped embedding-based way matching using all-MiniLM-L6-v2. The corpus currently contains only global ways (`~/.claude/hooks/ways/`). But Claude Code's way system supports project-local ways at `/path/to/project/.claude/ways/`, and these participate in matching via BM25 and NCD — the embedding engine should cover them too.

Projects are tracked by Claude Code in `~/.claude/projects/<encoded-path>/`. Each may have its own way tree at the project root's `.claude/ways/`. These ways follow the same n-deep progressive disclosure structure as global ways (ADR-105) and may change significantly between sessions as projects evolve.

The gap: a user working in a project with custom ways gets BM25 fallback matching for those ways while global ways get embedding-quality matching. This creates an inconsistent experience — the same prompt triggers different matching quality depending on whether the way is global or project-local.

Additionally, runtime artifacts need clear separation from source. The corpus is a cache (generated from way files), not source data. ADR-108 moved it to `${XDG_CACHE_HOME:-~/.cache}/claude-ways/user/`. All runtime artifacts — binary, model, corpus, and now the embedding manifest — live outside `~/.claude/`.

## Decision

### Unified Corpus Generation

`generate-corpus.sh` scans both global and project-local ways into a single corpus:

1. Embed global ways (`~/.claude/hooks/ways/`) — same as today
2. Scan `~/.claude/projects/` for decoded project paths
3. For each project with `.claude/ways/`:
   a. Lint the ways (must pass to proceed)
   b. Check the inclusion marker at `<project>/.claude/.ways-embed`
   c. Embed included ways into the same corpus

Corpus IDs follow Claude Code's native project encoding. Global ways keep their current format (`softwaredev/code/testing`). Project ways are namespaced by encoded project path, mirroring `~/.claude/projects/` conventions: `<encoded-path>/<way-tree-path>`.

Way trees are n-deep (progressive disclosure, ADR-105), so IDs reflect the full tree path — no fixed domain/way depth assumption.

### Inclusion Markers

A file at `<project>/.claude/.ways-embed` controls whether that project's ways are embedded:

| State | Behavior |
|-------|----------|
| No marker, valid ways found | Create marker = `include`, embed |
| No marker, no ways | Skip silently |
| Marker = `include` | Embed |
| Marker = `disinclude` | Skip, warn if valid ways exist |
| Ways fail lint | Never embed, regardless of marker |

Writing to `<project>/.claude/` is consistent with Claude Code's own behavior — it already writes memory, `settings.local.json`, and permissions there.

### Manifest-Based Staleness Detection

A manifest at `${XDG_CACHE_HOME}/claude-ways/user/embed-manifest.json` records what was embedded and when:

```json
{
  "generated": "2026-03-23T14:30:00Z",
  "global": {
    "ways_count": 58,
    "last_commit": "abc1234"
  },
  "projects": {
    "-home-aaron-myproject": {
      "path": "/home/aaron/myproject",
      "ways_count": 3,
      "last_commit": "def5678",
      "uncommitted": false
    }
  }
}
```

### Session-Start Staleness Check

At session start (cheap, no embedding work):

1. Read the manifest
2. For each project in the manifest, compare:
   - Git log date of `.claude/ways/` vs manifest's `last_commit`
   - Check for uncommitted changes to `.claude/ways/`
3. For projects not in the manifest, check if `.claude/ways/` exists (new project)
4. If any project is stale, or a new project is discovered, trigger regen

This is a **trilemma** of three timestamps:
- **Embedding date** — when the corpus was last generated
- **Project ways state** — commit hashes and uncommitted changes
- **Manifest** — what was included last time

The check is stat/git-log level — no embedding computation. At worst it runs every session start. User-scope ways are relatively static; project-scope ways evolve significantly, making this check worthwhile.

### Staleness is Harmless

If a project is deleted or its ways removed, stale embeddings remain in the corpus but never match — no way file backs them at runtime. Next regen naturally drops them. No eager purge, no reconciliation. Corpus regen is append-from-scan, not diff-and-reconcile.

## Consequences

### Positive

- Project-local ways get embedding-quality matching (98%) instead of BM25 fallback (91%)
- Single corpus, single embedding space — no per-project model overhead
- Staleness check is cheap and non-blocking (stat + git log, no embedding)
- Lint-gating prevents broken or untrusted ways from entering the embedding
- Inclusion markers give projects control without global configuration
- Manifest enables incremental regen — only re-embed when something changed

### Negative

- Session start gains a filesystem scan across `~/.claude/projects/` (should be fast — it's directory listing + git log)
- Regen cost grows linearly with project count (each project's ways are additional embedding work, ~20ms per way)
- Manifest is another file to manage in XDG cache (but it's a cache — loss just triggers full regen)
- Inclusion markers in project `.claude/` directories are a write outside the framework's own tree

### Neutral

- BM25 and NCD fallback paths already handle project-local ways — this extends existing behavior to the embedding tier
- The scanner (`match-way.sh`) needs no changes for matching — it already resolves project overrides at runtime. The change is in corpus generation only.
- Progressive disclosure (ADR-105) works the same way for project ways — parent/child relationships, sibling coverage, depth tracking all apply

## Alternatives Considered

### Per-project corpus files

Generate a separate corpus per project, load multiple at match time.

Rejected: multiplies file I/O, complicates the scanner, and breaks the "one embedding space" property that makes cosine similarity scores comparable across all ways.

### Embed on every session start unconditionally

Skip the manifest, just regenerate every time.

Rejected: embedding 58+ ways takes ~2 seconds. With multiple projects, this could grow to 5-10 seconds — noticeable on every session start. The manifest check is effectively free by comparison.

### Store corpus in project `.claude/` alongside ways

Each project manages its own embedding cache.

Rejected: violates the XDG separation principle. Runtime artifacts belong in `~/.cache/`, not in project trees. Also breaks unified matching.

### No project-scope embedding (status quo)

Keep embedding for global ways only, rely on BM25 for project ways.

Rejected: creates an inconsistent matching experience. The whole point of ADR-108 was that BM25 can't distinguish meaning — that limitation applies equally to project ways.
