---
match: regex
pattern: release|changelog|tag|version.?bump|bump.?version|npm.?publish|cargo.?publish
---
# Release Way

## Generate Changelog

```bash
# Commits since last tag
git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD~20")..HEAD
```

Format using Keep a Changelog:
```
## [X.Y.Z] - YYYY-MM-DD
### Added
### Changed
### Fixed
### Removed
```

## Infer Version Bump

From commit messages since last tag:
- Any `feat!:` or `BREAKING CHANGE` → **major**
- Any `feat:` → **minor**
- Only `fix:`, `docs:`, `chore:` → **patch**

## Update Version

Detect the version file (package.json, Cargo.toml, pyproject.toml, version.txt) and update it.

## Do Not

- Explain what semantic versioning is — just apply it
- List human process steps (deploy, announce) — produce artifacts Claude can generate
