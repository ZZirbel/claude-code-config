# ADR-110 Iteration 2: Documentation, Tooling, and Validation

**Branch:** `staging/ADR-110`
**Predecessor:** Iteration 1 completed Phases 1-5 + file rename + code review fixes (8 commits)
**Context:** ADR-110 separated provenance to sidecars, added epistemic/See Also conventions, renamed way.md → {name}.md. The structural changes are done. This iteration updates everything that references the old structure and builds the remaining tooling.

## Phase 2.1: Update ADRs to reflect what we actually built

**Why:** ADR-110 was written before the file rename decision. ADR-107 still references `way-{lang}.md` without noting the base file also renamed.

**Files:**
- `docs/architecture/system/ADR-110-way-file-separation-and-graph-compatible-structure.md`
- `docs/architecture/system/ADR-107-way-match-corpus-batch-mode-and-locale-support.md`

**Changes to ADR-110:**
- Section 3 ("Keep frontmatter matching-only") — update to reflect that files are now `{dirname}.md` not `way.md`
- Section 4 (derived artifacts) — remove mention of `.vault/` with uniquely-named symlinks; the files themselves are now unique
- Add a section or note explaining the file rename decision and rationale (Logseq/graph compatibility, unique filenames for any tool)
- Update all examples that show `way.md` to show `{name}.md`

**Changes to ADR-107:**
- Phase 3 locale convention: `way-{lang}.md` becomes `{name}-{lang}.md` (e.g., `quality-es.md`)
- Scanner logic section: update the file discovery description
- Interaction with ADR-110 section: update file examples

## Phase 2.2: Update documentation and templates

**Why:** User-facing docs and templates still reference `way.md` and `check.md`.

**Files to check and update:**
- `docs/hooks-and-ways/*.md` — any file referencing way.md naming convention
- `hooks/ways/init-project-ways.sh` — template text (line ~39-44 area, partially done)
- `hooks/ways/frontmatter-schema.yaml` — comments still reference way.md
- `CONTRIBUTING.md` — if it mentions way file naming
- `hooks/ways/meta/knowledge/authoring/authoring.md` — this way teaches how to write ways; file naming guidance is stale
- `hooks/ways/meta/knowledge/knowledge.md` — may reference way.md in its description of the system
- `hooks/ways/meta/skills/skills.md` — if it cross-references way file structure

**Approach:** `grep -rn "way\.md" docs/ hooks/ways/meta/knowledge/ CONTRIBUTING.md` to find all references. Update each. Don't change the frontmatter schema field names (those are the field names, not filenames).

## Phase 2.3: Update ways-tests skill

**Why:** The SKILL.md teaches scoring and testing. Its examples reference `way.md`.

**File:** `skills/ways-tests/SKILL.md`

**Changes:**
- Update file path examples to use `{name}.md`
- Update any instructions that say "find way.md" or "create way.md"
- Check if the skill's scoring commands assume `way.md` filenames

## Phase 2.4: Regenerate embedding corpus and validate pipeline

**Why:** `generate-corpus.sh` was updated to find `*.md` instead of `way.md`, but the corpus hasn't been regenerated against the renamed files. The embedding engine needs to see the new filenames.

**Steps:**
1. Run `make setup` or manually: `bash tools/way-match/generate-corpus.sh ~/.claude/hooks/ways`
2. Verify corpus has entries for all semantic ways: `wc -l ~/.cache/claude-ways/user/ways-corpus.jsonl`
3. Run `way-embed generate` to rebuild embeddings
4. Test matching: try a prompt that should trigger a known way and verify it fires
5. Run `hooks/ways/lint-ways.sh` — should still be 0 errors
6. Run `governance/governance.sh` — should show 17 provenance, 85+ ways scanned

**If corpus generation fails:** The `id` derivation changed from `${relpath%/way.md}` to `${relpath%/*}`. If any downstream consumer (way-match binary, embedding cache) depends on specific ID formats, those will break and need investigation.

## Phase 2.5: Graph artifact generator (new tooling)

**Why:** ADR-110 specifies a `ways-graph.jsonl` export — nodes and edges in a tool-agnostic format.

**Create:** `tools/ways-graph-generator.sh` (or `.py`)

**Reusable infrastructure:**
- `hooks/ways/embed-lib.sh` — `content_hash()`, `json_escape()`, path utils
- `tools/way-match/generate-corpus.sh` — scanning pattern
- The `<!-- epistemic: X -->` comments in way files
- The `## See Also` sections in way files

**Output format (JSONL):**
```jsonl
{"type":"node","id":"code/quality","domain":"softwaredev","epistemic":"heuristic","description":"..."}
{"type":"edge","source":"code/quality","target":"code/testing","rel":"see_also","label":"quality requires test coverage"}
```

**Extraction logic:**
- Nodes: scan all way files, extract id (dirname), domain (first path component), epistemic (HTML comment), description (frontmatter)
- Edges: parse `## See Also` sections, extract `name(domain)` references and descriptions

**Validation:** `jq` each line. Node count should match way count (~84). Edge count should match See Also reference count (~80).

## Phase 2.6: `way-embed siblings` subcommand (C++)

**Why:** Way-vs-way cosine similarity as an authoring compass. The embedding engine scores prompt-vs-way but not way-vs-way.

**File:** `tools/way-embed/way-embed.cpp`

**Changes:**
- New `cmd_siblings()` function
- Reuses existing `cosine_similarity()` (around line 285) and corpus loading
- Input: `--corpus FILE --model FILE --id WAY_ID [--threshold N]`
- Output: sorted list of way IDs and similarity scores above threshold
- For `--id all`: output full NxN matrix (useful for graph generator)

**Build:** `make -C tools/way-embed` — the existing Makefile handles compilation. CI builds for 4 platforms.

**Validation:** `way-embed siblings --corpus ... --model ... --id code/quality` should show code/testing and code/errors scoring higher than unrelated ways.

## Phase 2.7: Logseq setup tool (deferred, design only)

**Why:** We decided not to ship Logseq config. Instead, a tool that configures it after the user opens their ways directory in Logseq.

**Design notes for when we build it:**
- Script that writes `logseq/config.edn` with:
  - `:property-pages/enabled? false`
  - `:ignored-page-references-keywords` listing all frontmatter field names
  - `:hidden` excluding non-way directories if needed
- Could be a `make logseq-setup` target or a standalone script
- Should be idempotent — safe to re-run after way schema changes add new frontmatter fields
- Not blocking anything else

## Execution order

```
2.1 (ADR updates) ─────→ can start immediately, no dependencies
2.2 (docs/templates) ──→ can start immediately, no dependencies
2.3 (ways-tests skill) → can start immediately, no dependencies
2.4 (corpus regen) ────→ do after 2.2 (in case doc updates change way files)
2.5 (graph generator) ─→ do after 2.4 (needs working corpus)
2.6 (siblings cmd) ────→ independent, needs build environment
2.7 (logseq tool) ─────→ deferred
```

2.1, 2.2, and 2.3 can run in parallel — they touch different files.
2.4 is the validation gate before building new tooling.
2.5 and 2.6 are independent of each other.

## How to start a new session

```
git checkout staging/ADR-110
cat .claude/todo-ADR-110-iteration-2.md
```

The branch has all iteration 1 work. Start with Phase 2.1 or whichever phase makes sense.
