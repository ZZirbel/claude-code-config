---
match: semantic
description: writing unit tests, test coverage, mocking dependencies, test-driven development
vocabulary: unittest coverage mock tdd assertion jest pytest rspec testcase
commands: npm\ test|yarn\ test|jest|pytest|cargo\ test|go\ test|rspec
threshold: 0.54
scope: agent, subagent
---
# Testing Way

## What to Generate

For each function under test, cover:
1. **Happy path** — expected input produces expected output
2. **Empty/null input** — handles absence gracefully
3. **Boundary values** — min, max, off-by-one, empty collections
4. **Error conditions** — invalid input, dependency failures

## Structure

- Arrange-Act-Assert: setup, call, verify
- Name tests: `should [behavior] when [condition]`
- One logical assertion per test — test one behavior, not one line
- Tests must be independent — no shared mutable state between tests

## What to Assert

- Observable outputs and side effects only
- Never assert on method call counts or internal variable values
- If you need to reach into private state, the design needs rethinking

## Mocking

- Mock external dependencies (network, filesystem, databases)
- Do not mock the code under test or its internal helpers
- Prefer fakes (in-memory implementations) over mock libraries when practical

## Project Detection

Detect the test framework from project files (package.json, requirements.txt, Cargo.toml, go.mod). Follow its conventions for file placement and naming.
