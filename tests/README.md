# Testing the Ways System

Three test layers, from fast/automated to slow/interactive.

## 1. Fixture Tests (BM25 vs NCD scorer comparison)

Runs 32 test prompts against a fixed 7-way corpus. Compares BM25 binary against gzip NCD baseline. Reports TP/FP/TN/FN for each scorer.

```bash
bash tools/way-match/test-harness.sh
```

Options: `--bm25-only`, `--ncd-only`, `--verbose`

**What it covers**: Scorer accuracy, false positive rate, head-to-head comparison. Tests direct vocabulary matches, synonym/paraphrase variants, and negative controls.

**Current baseline**: BM25 26/32, NCD 24/32, 0 FP for both.

## 2. Integration Tests (real way files)

Scores 31 test prompts against actual `way.md` files extracted from the live ways directory. Tests the real frontmatter extraction pipeline.

```bash
bash tools/way-match/test-integration.sh
```

**What it covers**: End-to-end scoring with real way vocabulary, multi-way discrimination (does the right way win?), threshold behavior with actual threshold values.

**Current baseline**: BM25 27/31 (0 FP), NCD 15/31 (3 FP).

## 3. Activation Test (live agent + subagent)

Interactive test protocol that verifies the full hook pipeline in a running Claude Code session. Tests regex matching, BM25 semantic matching, negative controls, and subagent injection.

**To run**: Start a fresh session from `~/.claude/` and type:

```
read and run the activation test at tests/way-activation-test.md
```

Claude reads the test file (avoiding prompt-hook contamination), then walks you through 7 steps:

| Step | Who | Tests |
|------|-----|-------|
| 1 | Claude | Session baseline (no premature domain activation) |
| 2 | User types prompt | Regex pattern matching (commits way) |
| 3 | User types prompt | BM25 semantic matching (security way) |
| 4 | User types prompt | Negative control (no false positives) |
| 5 | Claude | Subagent injection (Testing Way via SubagentStart) |
| 6 | Claude | Subagent negative (no injection on irrelevant prompt) |
| 7 | Claude | Summary table |

Takes about 3 minutes. **Current baseline**: 6/6 PASS.

## Ad-Hoc Vocabulary Testing

The `/test-way` skill scores a prompt against all semantic ways and reports BM25 scores. Use it during vocabulary tuning to check discrimination between ways.

```
/test-way "write some unit tests for this module"
```

## When to Run Which

| Scenario | Test |
|----------|------|
| Changed `way-match.c` or rebuilt binary | Fixture tests + integration tests |
| Changed a way's vocabulary or threshold | Integration tests + `/test-way` |
| Changed hook scripts (check-*.sh, inject-*.sh, match-way.sh) | Activation test |
| Added a new way | Integration tests + `/test-way` + activation test |
| Sanity check after merge | All three |
