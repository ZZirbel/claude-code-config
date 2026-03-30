# ADR-111 Phase 2: Hook Infrastructure Consolidation

**Branch:** `staging/ADR-111`
**Predecessor:** Phase 1 built the `ways` CLI (9 subcommands), rewired callers, deleted replaced scripts (15 commits).
**Context:** The `ways` binary is the runtime. Hooks are bash dispatchers that call it. Next step: absorb the heavy hook infrastructure scripts into `ways` subcommands, leaving hooks as truly thin glue.

## What stays as bash (and why)

Hook entry points must be bash — Claude Code invokes them as shell commands:
- `check-prompt.sh` — reads stdin JSON, dispatches to matchers
- `check-bash-pre.sh` — command pattern intercept
- `check-file-pre.sh` — file edit intercept
- `check-task-pre.sh` — task intercept
- `check-response.sh` — response topic extraction

Tiny utilities (under 40 lines, no logic worth compiling):
- `epoch.sh` — writes /tmp markers
- `detect-scope.sh` — checks env vars
- `clear-markers.sh` — rm markers
- `log-event.sh` — appends JSONL
- `mark-tasks-active.sh` — 6 lines

Macros are bash by design — they run arbitrary shell:
- `macro.sh` + all domain-specific `macro.sh` files

## Phase 2.1: Delete lint-ways.sh

**Why:** `ways lint` is a complete replacement. The only remaining caller is `lint-ways.sh` itself being invoked from test pipelines and the `/ways-tests` skill.

**Steps:**
1. Search for all references to `lint-ways.sh` in hooks, skills, commands, tests
2. Replace with `ways lint` (or `ways lint <path>` for targeted linting)
3. Delete `lint-ways.sh`
4. Verify: `ways lint` and `ways lint --check` still work

## Phase 2.2: `ways show` — absorb the display cluster

**Why:** `show-way.sh` (222 lines), `show-check.sh` (169 lines), and `show-core.sh` (162 lines) = 553 lines of content rendering. They handle session markers, frontmatter stripping, macro dispatch, and content formatting. This is the second most-called code path after matching.

**New subcommand:**
```
ways show <way-id> --session <SESSION_ID> [--channel <keyword|semantic>]
ways show --core --session <SESSION_ID>
ways show --check <way-id> --session <SESSION_ID>
```

**What it does:**
- Check session marker (`/tmp/.claude-way-{name}-{SESSION_ID}`) — skip if already shown
- Read way file, strip frontmatter
- Output content to stdout (the hook captures and injects this)
- Create session marker
- Return exit code: 0 = shown, 1 = already shown (idempotent)

**What stays in bash:**
- Macro dispatch (`macro.sh`) — must stay bash, `ways show` calls it via subprocess if the way has `macro: prepend|append`
- The hook entry point still reads the show output and prints it

**Files deleted after:**
- `show-way.sh`
- `show-check.sh`
- `show-core.sh`

## Phase 2.3: `ways status` — absorb embed-status.sh

**Why:** 301 lines of diagnostic reporting. Already partially broken by `embed-lib.sh` deletion (we patched it but it's fragile). Natural fit as `ways status`.

**New subcommand:**
```
ways status [--json]
```

**Reports:** engine in use, binary/model/corpus state, way counts, project inclusion, staleness.

**File deleted after:** `embed-status.sh`

## Phase 2.4: `ways check-state` — absorb check-state.sh

**Why:** 206 lines handling state-based triggers (context-threshold, file-exists, session-start). These are deterministic checks that don't need bash.

**New subcommand:**
```
ways check-state --session <SESSION_ID> --project <PROJECT_DIR> [--json]
```

**Output:** list of way IDs whose state triggers are satisfied.

**File deleted after:** `check-state.sh`

## Phase 2.5: `ways stats` — absorb stats.sh

**Why:** 348 lines of event/usage statistics. Reads `stats/events.jsonl`, computes firing counts, timing, etc.

**New subcommand:**
```
ways stats [--json] [--since <date>]
```

**File deleted after:** `stats.sh`

## Phase 2.6: Simplify remaining hook scripts

After phases 2.1-2.5, the hook entry points become much thinner:

**check-prompt.sh** (currently 101 lines) becomes ~30 lines:
```bash
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty' | tr '[:upper:]' '[:lower:]')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# Bump epoch
source "${WAYS_DIR}/epoch.sh"
bump_epoch "$SESSION_ID"

# Scan and show matching ways
for way_id in $(ways scan --prompt "$PROMPT" --session "$SESSION_ID"); do
  ways show "$way_id" --session "$SESSION_ID"
done
```

This requires a `ways scan` subcommand that combines matching + filtering:
```
ways scan --prompt <text> --session <SESSION_ID> [--project <dir>]
```
Output: one way ID per line for ways that match AND pass scope/precondition gates.

## Phase 2.7: Governance consolidation

**Why:** `governance.sh` (543 lines) and `provenance-verify.sh` orchestrate provenance reporting. Most of the logic is JSON manipulation that `ways` handles better.

**New subcommand:**
```
ways governance [--trace <way>] [--control <pattern>] [--gaps] [--json]
```

**Files deleted after:** `governance.sh`, `provenance-verify.sh`

## Execution order

```
2.1 (delete lint-ways.sh)  ─→ trivial, do first
2.2 (ways show)            ─→ biggest win, most complex
2.3 (ways status)          ─→ standalone, no dependencies
2.4 (ways check-state)     ─→ after 2.2 (show depends on state)
2.5 (ways stats)           ─→ standalone
2.6 (simplify hooks)       ─→ after 2.2 and 2.4
2.7 (governance)           ─→ standalone, can defer
```

2.1 is safe to do immediately. 2.2 is the high-value target. 2.3 and 2.5 are independent. 2.6 is the payoff that makes hooks truly thin.

## How to resume

```
git checkout staging/ADR-111
cat .claude/todo-ADR-111-phase2.md
```

The branch has all Phase 1 work. Start with 2.1 (trivial), then 2.2 (the big one).
