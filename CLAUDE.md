# ADR-Driven Development Config

ADR-driven workflow with GitHub-first collaboration.

**Instructions are injected via hooks, not this file.**

Instructions are loaded at critical moments to maintain relevance:
- **SessionStart** - Fresh context when sessions begin
- **PreCompact** - Fresh context after compaction events

This approach ensures guidance stays active in the conversation window rather than being buried as distant system prompts.

See `hooks/ways/core.md` for the base guidance and `hooks/ways/*.md` for contextual instructions.
