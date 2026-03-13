---
name: ways-tests
description: Score way matching, analyze vocabulary, and validate frontmatter. Use when testing how well a way matches prompts, checking for vocabulary gaps, or validating way files.
allowed-tools: Bash, Read, Glob, Grep, Edit
---

# ways-tests: Way Matching & Vocabulary Tool

Test how well a way matches sample prompts, analyze vocabulary for gaps, and validate frontmatter.

## Usage

```
/ways-tests score <way> "prompt"          # Score one way against a prompt
/ways-tests score-all "prompt"            # Rank all ways against a prompt
/ways-tests suggest <way>                 # Analyze vocabulary gaps
/ways-tests suggest <way> --apply         # Update vocabulary in-place
/ways-tests suggest --all [--apply]       # Analyze/update all ways
/ways-tests lint <way>                    # Validate frontmatter
/ways-tests lint --all                    # Validate all ways
/ways-tests check <check> "context"       # Test check scoring curve
/ways-tests check-all "context"           # Rank all checks against context
```

## Resolving Way Paths

When the user gives a short name like "security" instead of a full path:
1. Check `$CLAUDE_PROJECT_DIR/.claude/ways/` first (project-local)
2. Then check `~/.claude/hooks/ways/` recursively for `*/security/way.md`
3. If multiple matches, list them and ask the user to pick

## Score Mode

Use the `way-match` binary at `~/.claude/bin/way-match`:

```bash
# Extract frontmatter fields from the way.md
description=$(awk 'NR==1 && /^---$/{p=1;next} p&&/^---$/{exit} p && /^description:/{gsub(/^description: */,"");print;exit}' "$wayfile")
vocabulary=$(awk 'NR==1 && /^---$/{p=1;next} p&&/^---$/{exit} p && /^vocabulary:/{gsub(/^vocabulary: */,"");print;exit}' "$wayfile")
threshold=$(awk 'NR==1 && /^---$/{p=1;next} p&&/^---$/{exit} p && /^threshold:/{gsub(/^threshold: */,"");print;exit}' "$wayfile")

# Score with BM25
~/.claude/bin/way-match pair \
  --description "$description" \
  --vocabulary "$vocabulary" \
  --query "$prompt" \
  --threshold "${threshold:-2.0}"
# Exit code: 0 = match, 1 = no match
# Stderr: "match: score=X.XXXX threshold=Y.YYYY"
```

### Cross-Way Context (automatic)

**When scoring a single way, always include cross-way context.** After showing the target way's score, automatically run a score-all for the same prompt and display the top 5-8 ways as a ranking table. This answers the real questions:

- Does this way **win** when it should?
- Does it **defer** to the right way when another is more specific?
- Are there **unhealthy overlaps** where two ways compete at similar scores?
- Do any **unexpected ways** fire that shouldn't?

Present as:

```
=== "add a make target for linting" ===

Target: softwaredev/environment/makefile
  Score: 5.2716  Threshold: 1.5  Result: MATCH

Cross-way ranking:
  Score   Thr    Match  Way
  ------  -----  -----  ---
  5.2716  1.5    YES    softwaredev/environment/makefile  ← target
  1.9580  2.0    no     softwaredev/docs/standards
  0.0000  2.0    no     softwaredev/environment/deps
  ...

Assessment: Clean win. No competing ways above threshold.
```

Flag these patterns:
- **Overlap**: Two ways both match with scores within 20% of each other → potential conflict
- **False dominance**: Another way scores higher than the target → the target may need vocabulary tuning
- **Healthy co-fire**: Both match but serve complementary purposes → note as expected

## Score-All Mode

For each way.md file found (project-local + global), extract description+vocabulary and run `way-match pair`. Display results as a ranked table:

```
Score   Threshold  Match  Way
------  ---------  -----  ---
4.7570  2.0        YES    softwaredev/security
2.3573  2.0        YES    softwaredev/api
1.6812  2.0        no     softwaredev/debugging
```

Include ways that have pattern matches too (mark those as "REGEX" in the Match column).

### Prompt Battery (automatic for score-all)

When running score-all without a specific prompt, or when the user asks for a broad evaluation, generate a battery of 8-12 diverse prompts that stress-test coverage:

- 2-3 prompts that should clearly match one specific way
- 2-3 prompts that should trigger healthy co-fires (multiple ways relevant)
- 2-3 prompts at the boundary (could go either way)
- 2-3 prompts that shouldn't match any way strongly

This gives a landscape view of how the way ecosystem behaves.

## Suggest Mode

Use the `way-match suggest` command:

```bash
~/.claude/bin/way-match suggest --file "$wayfile" --min-freq 2
```

Output is section-delimited (GAPS, COVERAGE, UNUSED, VOCABULARY). Parse and display readably:

```
=== Vocabulary Analysis: softwaredev/code/security ===

Gaps (body terms not in vocabulary, freq >= 2):
  parameterized  freq=3
  endpoints      freq=2

Coverage (vocabulary terms found in body):
  sql            freq=3
  secrets        freq=3

Unused (vocabulary terms not in body):
  owasp, csrf, cors   (catch user prompts, not body text — likely intentional)

Suggested vocabulary line:
  vocabulary: <current> <+ gaps>
```

The UNUSED section is informational — unused vocabulary terms are often intentional (they catch user query terms that don't appear in the way body). Don't automatically remove them.

### Suggest + Apply

When `--apply` is specified:

1. **Git safety check**: Verify the way file is inside a git worktree
2. **If NOT git-tracked**: Warn and refuse unless `--force` is also specified
3. **If git-tracked**: Replace the vocabulary line, show diff, report count
4. **For `--all --apply`**: Process each way that has gaps, showing progress

## Lint Mode

Validate way frontmatter:

- `description` must be present
- If vocabulary present: check both description and vocabulary exist
- If `pattern` present: verify valid regex
- `threshold` must be numeric if present
- `scope` values must be valid (agent, subagent, teammate)
- For check.md files: verify `## anchor` and `## check` sections exist, and parent way.md exists

## Check Mode

Simulates the check scoring curve:

```bash
/ways-tests check design "editing architecture file" --distance 20 --fires 0
```

Displays match score, distance factor, decay factor, effective score, and simulates successive firings until decay silences the check.

## Evaluation Guidelines

When presenting results, always include an **assessment** that interprets the numbers:

- **Clean win**: Target way is the clear top scorer with daylight to the next
- **Healthy co-fire**: Multiple ways fire but serve complementary roles (e.g., `deps` + `makefile` for "install npm dependencies")
- **Overlap concern**: Two ways compete at similar scores for the same prompt — may need vocabulary differentiation or threshold tuning
- **False negative**: Target way doesn't fire for a prompt it clearly should — vocabulary gap
- **False positive**: Way fires strongly for a prompt it shouldn't own — vocabulary too broad

## Notes

- The `way-match` binary must exist at `~/.claude/bin/way-match`. If missing, report that BM25 is unavailable and suggest building it.
- When displaying results, use human-readable format, not raw machine output.
- Check scoring uses `awk` for floating-point math.
