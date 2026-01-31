# Matching Modes

How ways decide when to fire.

## Overview

Each way declares a matching strategy in its YAML frontmatter. The strategy determines what input is tested and how similarity is measured.

| Mode | Speed | Precision | Best For |
|------|-------|-----------|----------|
| **Regex** | Fast | Exact | Known keywords, command names, file patterns |
| **Semantic** | Fast | Fuzzy | Broad concepts that users describe many ways |
| **Model** | ~800ms | High | Ambiguous or high-stakes decisions |
| **State** | Fast | Conditional | Session conditions, not content matching |

## Regex Matching

The default and most common mode. Three fields can be tested independently:

- `pattern:` - tested against the user's prompt text
- `commands:` - tested against bash commands (PreToolUse:Bash)
- `files:` - tested against file paths (PreToolUse:Edit|Write)

A way can declare any combination. Each field is a standard regex evaluated case-insensitively against its input.

### Why regex is the default

Most ways have clear trigger words. "commit", "refactor", "ssh" - these don't need fuzzy matching. Regex is fast, predictable, and easy to debug. When a way misfires, you can read the pattern and understand why.

### Pattern design considerations

Patterns need to balance sensitivity and specificity:
- Too broad: `error` fires on "no errors found"
- Too narrow: `error_handling` misses "exception handling"
- Right: `error.?handl|exception|try.?catch` catches the concept without false positives

Word boundaries (`\b`) help with short words that appear inside other words. The `commits` way uses `\bcommit\b` to avoid matching "committee" or "commitment".

## Semantic Matching

For concepts that users express in varied language. "Make this faster", "optimize the query", "it's too slow" all mean the same thing but share few words.

### Two-technique approach

Semantic matching uses two independent techniques. Either succeeding triggers the way.

**Technique 1: Keyword counting**

The `vocabulary:` field lists domain-specific words. The prompt is scanned for these words (after stripping stopwords and short tokens). If 2+ vocabulary words appear, it's a match.

This handles the common case where users naturally use domain terminology.

**Technique 2: Gzip NCD (Normalized Compression Distance)**

NCD measures how much two texts share structural patterns. The intuition: if two strings are similar, concatenating them won't increase compressed size much because the compressor finds shared patterns.

```
NCD(a,b) = (C(ab) - min(C(a),C(b))) / max(C(a),C(b))
```

Where `C(x)` is the compressed size of `x`. Lower NCD = more similar.

### Why gzip NCD instead of embeddings

Embeddings would be more accurate but require an API call (latency, cost) or a local model (complexity, memory). Gzip NCD runs in pure bash using the `gzip` command that's already on every system. It's fast (~5ms), requires no dependencies, and provides surprisingly good results for short text comparison.

The threshold (default 0.58) was tuned empirically. Lower values require more similarity (stricter matching).

### Which ways use semantic matching

Ways covering broad concepts where keyword matching would be either too narrow or too noisy:
- `api` (0.55) - API design, endpoints, request handling
- `config` (0.54) - configuration, environment, settings
- `debugging` (0.53) - debugging, troubleshooting, investigation
- `design` (0.55) - architecture, patterns, system design
- `security` (0.52) - authentication, secrets, vulnerabilities
- `testing` (0.54) - unit tests, TDD, mocking

Security has the lowest threshold (most strict) because false negatives there are costlier than false positives.

## Model Matching

Spawns a minimal Claude subprocess to classify whether the user's prompt relates to the way's description. Returns yes/no.

```bash
claude -p --max-turns 1 --tools "" --no-session-persistence \
  "Does this user message relate to: ${DESCRIPTION}? Answer only 'yes' or 'no':"
```

### When to use model matching

Model matching adds ~800ms latency per evaluation. Use it only when:
- The concept is genuinely ambiguous (regex and semantic both misfire)
- The stakes of misfiring are high (security-sensitive operations)
- The way is rarely triggered (latency cost is infrequent)

Currently no ways in the default configuration use model matching, but the infrastructure exists for high-stakes project-local ways.

## State Triggers

Unlike the other modes, state triggers don't match against content. They evaluate session conditions.

### context-threshold

Monitors transcript size as a proxy for context window usage. The calculation:
- Claude's context window: ~155K tokens
- Estimated density: ~4 characters per token
- Total capacity: ~620K characters
- Threshold at 75%: fires when transcript exceeds ~465K characters

The transcript size is measured since the last compaction (identified by `"type":"summary"` markers in the transcript JSONL). A cache avoids rescanning the full transcript on every prompt.

Unlike other ways, context-threshold triggers **repeat on every prompt** until the condition is resolved (task list created). This is deliberate: it's an enforcement mechanism, not educational guidance.

### file-exists

Checks for a glob pattern relative to the project directory. Fires once (standard marker) if any matching file exists. Useful for detecting project state - e.g., whether tracking files exist.

### session-start

Always evaluates true. Uses the standard marker, so it fires exactly once on the first UserPromptSubmit after session start. Useful for one-time session initialization that doesn't belong in SessionStart hooks.
