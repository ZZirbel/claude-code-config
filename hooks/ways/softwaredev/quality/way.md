---
match: regex
pattern: solid.?principle|refactor|code.?review|code.?quality|clean.?up|simplify|decompos|extract.?method|tech.?debt
macro: append
scan_exclude: \.md$|\.lock$|\.min\.(js|css)$|\.generated\.|\.bundle\.|vendor/|node_modules/|dist/|build/|__pycache__/
scope: agent, subagent
provenance:
  policy:
    - uri: docs/hooks-and-ways/softwaredev/code-lifecycle.md
      type: governance-doc
  controls:
    - ISO/IEC 25010:2011 (Maintainability - Analyzability, Modifiability)
    - NIST SP 800-53 SA-15 (Development Process, Standards, and Tools)
    - IEEE 730-2014 (Software Quality Assurance Processes)
  verified: 2026-02-05
  rationale: >
    Measurable thresholds (file length, nesting depth, method count) operationalize
    ISO 25010 maintainability characteristics. Ecosystem convention enforcement
    reduces cognitive load and security-relevant coding errors per NIST SA-15.
---
# Code Quality Way

## Quality Flags — Act on These

| Signal | Action |
|--------|--------|
| File > 500 lines | Propose a split with specific module boundaries |
| File > 800 lines | Flag as priority — split before adding more code |
| Function > 3 nesting levels | Extract inner logic into named helper functions |
| Class > 7 public methods | Decompose — likely violating Single Responsibility |
| Function > 30-50 lines | Break into steps with descriptive names |

When the file length scan (macro output) shows priority files, call them out explicitly before proceeding with the task.

## Ecosystem Conventions

- Don't introduce patterns foreign to the language/ecosystem
- Examples to avoid:
  - Rust-style Result/Option in TypeScript
  - Monadic error handling where exceptions are standard
  - Custom implementations of what libraries already provide
