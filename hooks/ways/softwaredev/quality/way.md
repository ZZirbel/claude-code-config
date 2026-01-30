---
match: regex
pattern: solid.?principle|refactor|code.?review|code.?quality|clean.?up|simplify|decompos|extract.?method|tech.?debt
macro: append
scan_exclude: \.md$|\.lock$|\.min\.(js|css)$|\.generated\.|\.bundle\.|vendor/|node_modules/|dist/|build/|__pycache__/
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
