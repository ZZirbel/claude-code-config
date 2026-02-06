---
match: regex
pattern: commit|push.*(remote|origin|upstream)
commands: git\ commit
scope: agent, subagent
provenance:
  policy:
    - uri: docs/hooks-and-ways/softwaredev/code-lifecycle.md
      type: governance-doc
  controls:
    - NIST SP 800-53 CM-3 (Configuration Change Control)
    - SOC 2 CC8.1 (Change Management)
    - ISO/IEC 27001:2022 A.8.32 (Change Management)
  verified: 2026-02-05
  rationale: >
    Conventional commits create structured change records with type classification
    and justification. Atomic commits ensure each change is independently traceable
    and reversible. Together they implement auditable configuration change control.
---
# Git Commits Way

## Conventional Commit Format

- `feat(scope): description` - New features
- `fix(scope): description` - Bug fixes
- `docs(scope): description` - Documentation
- `refactor(scope): description` - Code improvements
- `test(scope): description` - Tests
- `chore(scope): description` - Maintenance

## Branch Names

- `adr-NNN-topic` - Implementing an ADR
- `feature/name` - New feature work
- `fix/issue` - Bug fixes
- `refactor/area` - Code improvements

## Rules

- Skip "Co-Authored-By" and emoji trailers
- Focus commit message on the "why" not the "what"
- Keep commits atomic - one logical change per commit
