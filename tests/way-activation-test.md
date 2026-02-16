# Way Activation Integration Test

## Instructions for Claude

Read this file with the Read tool — do NOT have the user paste it into chat.

You are running an integration test. This test verifies that contextual hooks fire correctly for both the parent agent (you) and for subagents you spawn.

**Your role**: Follow each step in order. Announce what step you are on, perform the action, then report the result against the expected outcome. Wait for the user to complete each USER step before moving on.

**Format your reports as**:
```
Step N: [description]
Result: PASS / FAIL / UNEXPECTED
Detail: [what happened vs what was expected]
```

After reading this file, begin with Step 1.

---

## Test Sequence

### Step 1 — Baseline: Verify session started clean

> **CLAUDE**: Check what content was injected at session start. List any system-reminder blocks you see. Look for domain-specific headings (like `# [Topic] Way`). Report what was delivered.

**Expected**: You should see general session startup content (available hooks listing, collaboration norms). You should NOT see domain-specific guidance about version control, cryptography, automated verification, or application hardening — those require specific vocabulary to activate.

---

### Step 2 — Keyword trigger (regex pattern)

> **USER**: Type exactly: `I need to commit these changes and push to origin`

> **CLAUDE**: After the user sends that message, check if you received new domain-specific content in a system-reminder. Look for guidance about message conventions, branch naming, or attribution rules. Report what fired.

**Expected**: The commits way should fire (regex pattern: `commit|push.*(remote|origin|upstream)`). You should see guidance about conventional commit format and branch naming.

---

### Step 3 — Semantic trigger (BM25)

> **USER**: Type exactly: `how should I hash passwords with bcrypt for our login system?`

> **CLAUDE**: Check if you received new domain-specific content. Look for guidance about vulnerability categories, credential handling, input validation, or defensive defaults. Report what fired.

**Expected**: The security way should fire via BM25 semantic matching (vocabulary includes bcrypt, hash, password, authentication, login). You should see detection rules and security defaults.

---

### Step 4 — Negative test (no false positive)

> **USER**: Type exactly: `what's the weather like today?`

> **CLAUDE**: Check if any NEW domain-specific content was injected. Report what you see.

**Expected**: No new hooks should fire. This prompt has zero overlap with any way vocabulary. If domain-specific content appears, that is a false positive — report which one.

---

### Step 5 — Subagent injection (the critical path)

> **CLAUDE**: Spawn a diagnostic subagent with this exact configuration:
> - Use the Task tool with subagent_type: `general-purpose`
> - Prompt: `DIAGNOSTIC: List every system-reminder block you received (first 80 chars of each). Note any structured headings or injected procedural content. Report what topics are covered and what formatting you see. Do not perform other actions. Background: write unit tests for a utility module with jest`
> - Name: `injection-probe`
>
> Report the subagent's findings.

**Expected**: The subagent should report receiving Testing Way content via a SubagentStart system-reminder block containing:
- "# Testing Way" heading
- Arrange-Act-Assert structure guidance
- Coverage categories (happy path, boundary values, error conditions)
- Mocking section

If the subagent sees NO injected content beyond the base configuration, the injection pipeline is broken.

---

### Step 6 — Subagent negative test

> **CLAUDE**: Spawn another diagnostic subagent:
> - Use the Task tool with subagent_type: `general-purpose`
> - Prompt: `DIAGNOSTIC: List every system-reminder block you received (first 80 chars of each). Note any structured headings or injected procedural content. Report what topics are covered. Do not perform other actions. Background: what time is it in Tokyo`
> - Name: `negative-probe`
>
> Report the subagent's findings.

**Expected**: The subagent should NOT receive domain-specific procedural content. The background phrase has no relevance to any hook vocabulary. Only base configuration content should appear. If domain-specific content (about code, operations, or tooling) appears, that is a false positive.

---

### Step 7 — Summary

> **CLAUDE**: Compile a summary table:
>
> | Step | Test | Expected | Result |
> |------|------|----------|--------|
> | 1 | Session baseline | No domain-specific hooks | ? |
> | 2 | Regex keyword match | Commits way fires | ? |
> | 3 | BM25 semantic match | Security way fires | ? |
> | 4 | Negative (no match) | Nothing fires | ? |
> | 5 | Subagent injection | Testing Way received | ? |
> | 6 | Subagent negative | No domain content received | ? |
>
> Report the final pass/fail count and any observations.
