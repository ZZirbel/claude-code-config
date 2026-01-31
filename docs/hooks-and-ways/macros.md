# Macros

Dynamic content generation for ways.

## What Macros Do

A way's static content (`way.md`) is the same every time it fires. Macros add dynamic content by running a shell script at trigger time. The script's stdout is combined with the static content based on the `macro:` frontmatter field.

```yaml
macro: prepend   # macro output appears before static content
macro: append    # macro output appears after static content
```

The macro script lives alongside the way file as `macro.sh` in the same directory.

## Why Macros Exist

Some guidance depends on project state that can't be known at authoring time:

- Does this project use ADR tooling? (adr/macro.sh checks for `docs/scripts/adr`)
- Is this a solo project or a team project? (github/macro.sh checks contributor count)
- Which files in this project are too long? (quality/macro.sh scans the codebase)

Static way content handles the universal guidance ("here's how to write good commits"). Macros handle the situational guidance ("this project has 3 files over 800 lines - here they are").

## Examples

### ADR Tooling Detection (softwaredev/adr)

Implements tri-state detection:

1. **Declined**: `.claude/no-adr-tooling` exists - outputs a one-liner noting the project opted out, stops suggesting installation
2. **Installed**: `docs/scripts/adr` exists - outputs a command reference table for the installed ADR tool
3. **Available**: Neither file exists - suggests installing ADR tooling with setup instructions

This prevents the way from repeatedly suggesting tooling the user has already decided against.

### Team Detection (softwaredev/github)

Queries the GitHub API for contributor count:
- Solo/pair project (1-2 contributors): relaxes PR requirements
- Team project (3+ contributors): recommends PRs, shows potential reviewers

Adapts the formality of GitHub workflow guidance to the actual collaboration context.

### File Length Scanner (softwaredev/quality)

Scans `git ls-files` for files exceeding length thresholds:
- **Priority** (>800 lines): files that likely need decomposition
- **Review** (>500 lines): files worth monitoring

Uses the `scan_exclude:` frontmatter field to skip files that are legitimately long (lock files, generated code, markdown).

## The Core Macro

`macro.sh` at the ways root (`~/.claude/hooks/ways/macro.sh`) generates the Available Ways table shown at session start. It scans all `way.md` files, extracts their trigger patterns from frontmatter, and formats them as a markdown table grouped by domain.

This is invoked by `show-core.sh` during SessionStart and referenced by `core.md` via `macro: prepend`.

## Security Model

### Global macros

Macros in `~/.claude/hooks/ways/` always execute. The user controls this directory, so trust is implicit.

### Project-local macros

Macros in `$PROJECT/.claude/ways/` are potentially untrusted (a cloned repo could include malicious scripts). These only execute if the project path is explicitly listed in `~/.claude/trusted-project-macros`.

If a project-local macro exists but the project isn't trusted, the way outputs a note:
> **Note**: Project-local macro skipped (add /path/to/project to ~/.claude/trusted-project-macros to enable)

This prevents supply-chain attacks through project-local way macros while allowing teams that trust their repos to use the full feature.
