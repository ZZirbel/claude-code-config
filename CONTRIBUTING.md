# Contributing

The recommended setup is to **fork this repo** and customize it for your own workflows. Add ways for your domain, tweak the triggers, build your own Lumon handbooks. Your fork stays yours.

When you build something that would benefit everyone — a new domain, a better trigger pattern, a macro that detects something clever — we'd love a PR back to upstream. The framework improves when people bring different workflows to it.

## Adding a Way

1. Create `hooks/ways/{domain}/{wayname}/way.md` with YAML frontmatter
2. Define your trigger: `pattern:` for regex, `match: semantic` for fuzzy matching
3. Write compact, actionable guidance (every token costs context)
4. Test it: trigger the pattern and verify the guidance appears once

See [docs/hooks-and-ways/extending.md](docs/hooks-and-ways/extending.md) for the full guide.

## Reporting Bugs

Open an issue. Include which hook or way is involved, your OS/shell, and any error output.

## Pull Requests

- Keep changes focused — one way or one fix per PR
- Test your trigger patterns against both positive and negative cases
- If adding a new domain, include a brief rationale in the PR description

## Code Style

It's all bash. Keep it portable (no bashisms that break on macOS default bash 3.2), use `shellcheck` if available, and keep scripts under 200 lines where possible.
