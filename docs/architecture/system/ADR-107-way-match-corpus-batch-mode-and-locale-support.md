---
status: Draft
date: 2026-03-20
deciders:
  - aaronsb
  - claude
related:
  - ADR-014
---

# ADR-107: Way-Match Corpus, Batch Mode, and Locale Support

## Context

ADR-014 introduced the `way-match` BM25 binary as a replacement for gzip NCD semantic matching. The binary works well — 0 false positives across 74 test fixtures, good recall on natural language prompts — but three limitations are now visible after scaling from 7 semantic ways to 55+.

### Stale IDF corpus

`way-match pair` mode (what the runtime scanners use) computes IDF against a hardcoded `BUILTIN_WAYS[]` array of 7 way descriptions baked into the C source (line 352-368 of `way-match.c`). This was the entire semantic corpus when the binary was written. With 55+ semantic ways, the IDF calculations are wrong — term rarity is computed against 7 documents when the real corpus is 55+. A term like "test" that appears in many ways still gets high IDF because the builtin only has one way containing it.

The binary already has a `score` mode that loads an external JSONL corpus for correct IDF. But `pair` mode — the one called 55 times per prompt by the scanners — ignores it.

### N process spawns per prompt

Each scanner (`check-prompt.sh`, `check-bash-pre.sh`, `check-file-pre.sh`) calls `way-match pair` once per semantic way. At 55 semantic ways, that's 55 process spawns per user prompt. Each spawn re-initializes the Snowball stemmer, re-tokenizes the query, and re-builds the (wrong) IDF from the builtin corpus. The `score` command already supports batch scoring — one invocation, all ways ranked — but the scanners don't use it.

### English-only

The Snowball Porter2 stemmer (`stem_UTF_8_english.h`) and the stopword list are English. The ways system is currently English, but Claude Code has a `language` setting and users in non-English locales would benefit from ways written in their language with appropriate stemming.

### Security boundary

Any evolution of the binary must respect a hard constraint: **runtime scanners must never write to `~/.claude/`**. Way matching happens during normal project work in arbitrary repositories. Writing to the user's config directory during a prompt evaluation would be a form of supply-chain poisoning — a project-level operation mutating user-global state. All writes to `~/.claude/` (corpus generation, binary rebuilds) are authoring operations invoked explicitly by the user.

## Decision

Evolve `way-match` in three phases, each independently shippable:

### Phase 1: External corpus file

Generate `hooks/ways/ways-corpus.jsonl` from all semantic way.md files. This file is:

- **Git-tracked** — committed to the repo like `bin/way-match`. It's a build artifact, not a runtime cache.
- **Regenerated during authoring** — `lint-ways.sh` and `/ways-tests` scoring regenerate it before any operation that reads it. This ensures the linter and scorer always see the current state.
- **Read-only at runtime** — scanners read the file if present, fall back to `BUILTIN_WAYS[]` if absent. No writes during prompt evaluation.

The corpus generator is a shell script (or a `way-match generate` subcommand) that:
1. Finds all `way.md` files with `description:` + `vocabulary:` fields
2. Extracts id, description, vocabulary, threshold from frontmatter
3. Emits one JSON line per way to `ways-corpus.jsonl`

`way-match pair` mode gains an optional `--corpus` flag. When provided, it loads the external corpus for IDF instead of `BUILTIN_WAYS[]`. The scanners pass `--corpus` if the file exists.

### Phase 2: Batch scoring

Replace N `pair` calls with a single `score` call per scanner. The scanner:
1. Calls `way-match score --corpus ways-corpus.jsonl --query "the prompt"`
2. Gets back all matching ways above their respective thresholds (tab-delimited)
3. Fires `show-way.sh` for each match

This reduces 55 process spawns to 1. The `score` command already exists and handles per-document thresholds. The scanner refactoring is in shell, not C.

The `pair` command remains available for single-way testing (used by `/ways-tests score`).

### Phase 3: Locale-aware ways

Locale support separates two concerns: **matching** (frontmatter vocabulary in the user's language) and **injection** (the way body Claude reads). These don't have to come from the same file.

Two tiers of localization:

**Tier 1 — Language-specific matchers, shared body.** `way-en.md` has the full body. `way-es.md` has only frontmatter with Spanish vocabulary — no body. The scanner matches on `way-es.md`'s frontmatter (using the Spanish stemmer) but injects `way-en.md`'s body. The stub says "I know how to match in this language" but defers to the English file for content.

**Tier 2 — Fully translated.** Both `way-en.md` and `way-fr.md` have frontmatter AND body in their respective languages. Full localization. Most expensive to maintain — the body content must be kept in sync across translations.

**Rejected: Polyglot frontmatter** (mixing vocabulary from multiple languages in one file). This doesn't work — the English Porter2 stemmer mangles Spanish/French morphology. "vulnerabilidades" stemmed by the English stemmer produces unpredictable results. Each language's vocabulary must be processed by its own stemmer, which means separate files with separate `--language` invocations. There is no cheap shortcut that avoids per-language files.

**Complete coverage requirement.** Adding a language is an all-or-nothing commitment across the entire way corpus. You cannot add Spanish stubs for 3 ways and leave the other 52 English-only — a Spanish user would get guidance for 3 topics and silence for the rest, which is worse than getting all guidance in English.

The linter enforces this: if any `way-es.md` exists anywhere in the tree, every way directory must have a `way-es.md` (Tier 1 stub minimum). Creating 5 language stubs in 5 different ways produces a lint explosion: `(66 ways * 5 languages) - 5 existing = 325 errors`. That's the honest cost of "we support 5 languages" made visible before you ship. The lint explosion is intentional — it's the quality gate showing you the commitment you're making. Each stub is small (frontmatter-only, ~5 lines), but the aggregate authoring and scoring work is real. This prevents casual, incomplete localization from degrading the user experience.

```
hooks/ways/softwaredev/code/security/
  way-en.md     # English: full frontmatter + body (Tier 3 base)
  way-es.md     # Spanish: frontmatter only, no body (Tier 2 stub)
  way-fr.md     # French: full frontmatter + body (Tier 3 translation)
```

**Scanner logic:**

```
1. Determine configured language from Claude Code settings
2. Look for way-{lang}.md in each way directory
3. If found and has body → match on its frontmatter, inject its body (Tier 3)
4. If found but no body → match on its frontmatter, inject way-en.md body (Tier 2)
5. If not found → match on way.md / way-en.md as today (Tier 1 / default)
```

The key principle: **frontmatter is for matching, body is for injection, and they can come from different files.** A way directory can have one file serving all roles, or several files dividing the work. The scanner combines the right frontmatter with the right body based on what exists.

**Schema addition:** `locale:` field in `frontmatter-schema.yaml`. The linter validates locale codes and checks that Tier 2 stubs (frontmatter-only files) have a corresponding file with a body.

**Binary changes — coupled rebuild required:** The stemmer, stopwords, and corpus are tightly coupled and must be rebuilt together when locale support lands. Currently all three are baked into the binary (English Porter2 stemmer as `#include`, stopwords as a C array, seed corpus as `BUILTIN_WAYS[]`). Phase 3 externalizes them:

- **Stemmers:** Snowball ships stemmers for 20+ languages. The binary links multiple Snowball stemmer modules and selects at runtime via `--language`. This is a compile-time decision — each supported language adds ~5-10KB to the binary.
- **Stopwords:** Move from a hardcoded C array to per-language stopword files in `tools/way-match/stopwords/` (e.g., `en.txt`, `es.txt`, `fr.txt`). These are small, source-auditable text files — same trust tier as the C source. The binary loads the appropriate file at startup based on `--language`, falling back to the baked-in English list if the file is absent.
- **Corpus:** The `ways-corpus.jsonl` gains a `locale` field per entry. IDF is computed over the full corpus regardless of locale — not within-locale. A small locale (3 Spanish ways) computed in isolation would have meaningless IDF where every term is rare. Computing IDF across all 55+ documents preserves discriminative power. The `--language` flag affects stemming and stopwords only, not IDF calculation.

All three components are rebuilt together. The supported language set is not declared in a config — it's discovered from what exists. The corpus generator scans all `way-*.md` files, collects the set of locale codes in use (from filenames: `way-en.md` → `en`, `way-es.md` → `es`), and the Makefile includes the corresponding Snowball stemmers and stopword files. Adding a new language is: add `way-{lang}.md` files with frontmatter, run the rebuild. The build system discovers the language, the linter validates the pieces, the binary includes the stemmer.

**Scope:** Most ways stay English-only. Tier 1 and 2 only exist where someone commits to full-corpus coverage for a language. The system degrades gracefully — no locale file means English, which is the current behavior.

### Phase 3 testing: Cross-language scoring validation

Multilingual way testing is fundamentally different from monolingual testing. You cannot translate an English test prompt and score it — you must generate an *independently natural* prompt expressing the same intent in the target language. "check the dependencies for vulnerabilities" and "verificar las dependencias por vulnerabilidades" are parallel expressions of the same intent, not translations of each other's vocabulary terms.

**Why this matters:** BM25 scores depend on vocabulary term overlap after stemming. The English stemmer reduces "vulnerabilities" to "vulner" and matches against "vulnerability" in the vocabulary. The Spanish stemmer reduces "vulnerabilidades" to "vulnerabil" and must match against Spanish vocabulary terms. These are completely independent scoring paths. A mechanically translated test prompt might use words that don't appear in the target vocabulary, producing misleading low scores that reflect bad test design, not bad vocabulary.

**Binary requirement:** The `--language` flag must select the correct Snowball stemmer and stopword list per invocation. Scoring English vocabulary with the Spanish stemmer (or vice versa) produces garbage. Each test invocation declares its language:

```
way-match pair --language en --description "..." --vocabulary "..." \
  --query "check dependencies for vulnerabilities" --threshold 2.0

way-match pair --language es --description "..." --vocabulary "..." \
  --query "verificar las dependencias por vulnerabilidades" --threshold 2.0
```

**Cross-language delta report:** The linter compares scores across languages for the same way. English is the baseline. Delta measures how well each locale's vocabulary is tuned relative to the English vocabulary:

```
=== Cross-Language Delta: softwaredev/code/security ===

  Language  Prompt                                          Score  Delta
  en        check dependencies for vulnerabilities          4.20   baseline
  es        verificar las dependencias por vulnerabilidades  3.85   -0.35
  fr        vérifier les dépendances pour vulnérabilités    2.10   -2.10 ⚠

  Assessment: French vocabulary needs tuning (delta > 1.0)
```

A delta within ~1.0 of the baseline indicates comparable vocabulary coverage. A delta beyond 1.0 indicates the target language vocabulary has gaps — missing terms, insufficient synonyms, or stemmer mismatch.

**Autonomous test prompt generation:** Claude generates parallel test prompts because it's multilingual. But the test design must be structured: "express this intent naturally in language X" — not "translate this English prompt." The distinction is critical because natural phrasing in each language uses different words, different idioms, different sentence structures. A French user asking about security doesn't think in translated English — they think in French. The test prompts must reflect that.

**Test fixture format extension:** The existing JSONL test fixtures gain a `language` field:

```jsonl
{"prompt":"check dependencies for vulnerabilities","expected_way":"security","language":"en"}
{"prompt":"verificar las dependencias por vulnerabilidades","expected_way":"security","language":"es"}
{"prompt":"vérifier les dépendances pour vulnérabilités","expected_way":"security","language":"fr"}
```

The test harness groups fixtures by language, runs each group with the appropriate `--language` flag, and reports per-language accuracy alongside the cross-language delta.

**Linter integration:** `lint-ways.sh` gains locale checks (not behind `--strict` — these are errors, not recommendations):
- Scan all way directories, collect every locale code found (from `way-{lang}.md` filenames)
- On first encounter of a non-English locale: check every other way directory for that locale. Flag every directory missing it. This is the complete-coverage enforcement — one `way-es.md` anywhere means `way-es.md` everywhere.
- For each `way-{lang}.md`, verify the language code is a valid Snowball stemmer language
- For Tier 1 stubs (frontmatter only), verify a body file (`way-en.md` or `way.md`) exists in the same directory
- If test fixtures exist for multiple languages, run cross-language delta and flag deltas > 1.0

## Consequences

### Positive

- Phase 1: Correct IDF across the real corpus. Immediate accuracy improvement with minimal code change.
- Phase 2: 55x fewer process spawns per prompt. Measurable latency reduction on every user interaction.
- Phase 3: Ways system becomes accessible to non-English users. Same architecture, same matching quality, different language.
- Phases are sequential but each is a shippable increment — Phase 1 improves accuracy alone, Phase 2 improves performance alone, Phase 3 requires both but adds locale support. No big-bang migration.
- The trust chain from ADR-014 is preserved: tier 0 (bash fallback) → tier 1 (source-auditable binary) → tier 1.5 (source-auditable binary + tracked corpus).

### Negative

- Phase 1: Another file to track in git. Regeneration adds a step to the authoring workflow (mitigated by integration with lint/score).
- Phase 2: Scanner refactoring changes the output parsing contract between shell and binary. Needs careful testing.
- Phase 3: Significant binary complexity (multi-stemmer, per-language stopwords). Translation maintenance burden grows with each locale.
- The corpus file can go stale if someone modifies ways without running the linter. This is a process discipline issue, not an architectural one — same as forgetting to rebuild after changing source.

### Neutral

- `BUILTIN_WAYS[]` stays in the binary as a fallback. It's wrong but it's better than nothing when the corpus file is absent.
- The `pair` command isn't removed — it's still useful for single-way testing via `/ways-tests`.
- Locale support doesn't require all ways to be translated. English is and remains the default.
- The defensive boundary (no runtime writes to `~/.claude/`) applies to all phases.

## Alternatives Considered

- **Embeddings (fastembed, ONNX, llamafile)**: Would solve the semantic gap ("make it faster" → performance) that BM25 can't handle. Rejected for now — BM25 at 0 FP with 55+ semantic ways is sufficient. Embeddings require shipping a model file (25-130MB), which changes the trust profile from "source-auditable" to "model-auditable." The defensible trigger for reconsidering: measurable false negatives in production that vocabulary tuning cannot fix, across a corpus that has outgrown manual curation. We're not there.
- **Runtime corpus regeneration**: Regen the JSONL on every prompt if any way.md is newer. Rejected — this writes to `~/.claude/` during project work, which is a poisoning vector. The corpus is a build artifact, not a cache.
- **Embed corpus in the binary**: Compile `ways-corpus.jsonl` into the binary as a C array (like `BUILTIN_WAYS[]` but generated). Would eliminate the external file. Rejected — requires recompiling the binary every time a way changes. The current model (binary rarely changes, corpus changes with ways) is more practical.
- **Move to Python/Node for matching**: Would make stemmer/locale swapping trivial (NLTK, etc). Rejected — adds a runtime dependency. The ways system runs on bash + coreutils + one static binary. That property is worth preserving.
- **Use Claude itself for matching**: The model reading the ways has world-class semantic understanding. Could we score relevance in-band? The old `model-match.sh` tried this via `claude -p` subprocesses. Rejected — Anthropic's ToS restricts programmatic Claude subscription usage, and subprocess latency is orders of magnitude worse than BM25. If Claude Code ever exposes an in-process scoring API, this becomes viable.

## References

- ADR-014: TF-IDF/BM25 Binary for Semantic Way Matching (predecessor)
- `tools/way-match/way-match.c`: Current implementation (907 lines)
- `hooks/ways/frontmatter-schema.yaml`: Authoritative field definitions
- [Snowball stemmer project](https://snowballstem.org/): Multi-language stemming algorithms
- Claude Code `language` setting: User locale preference
