# Rationale

Why this system exists and how it's designed.

## The Problem

Claude Code sessions start with a blank slate. Project conventions, workflow standards, and operational guardrails need to reach the model at the right moment - not all upfront (wasting context), not too late (after mistakes are made).

Static instruction files (CLAUDE.md) solve the "always present" case but can't respond to what's actually happening in a session. A commit message reminder is useless during a debugging session. Security guidance matters when editing auth code, not when writing docs.

## Three-Layer Model

This system separates concerns into three layers, each serving a different audience and purpose:

| Layer | Files | Audience | Optimized For |
|-------|-------|----------|---------------|
| **Policy** | `docs/hooks-and-ways/` | Humans | Understanding, rationale, 5W1H |
| **Reference** | `docs/hooks-and-ways.md` | Human-machine bridge | How the system works, data flow |
| **Machine guidance** | `hooks/ways/*/way.md` | Claude (LLM) | Terse, directive, context-efficient |

**Policy** is where organizational opinions live in prose. "We use conventional commits because..." - the kind of thing a new team member reads to understand why things are done a certain way.

**Reference** documents the machinery: which hooks fire when, how matching works, what scripts do. It's the system manual.

**Machine guidance** is the actual content injected into Claude's context window. These read differently from normal documentation - they're short, imperative, and structured for a language model to act on. A human can read them but might find the style terse. That's by design: every token in the context window costs capacity.

## Design Principles

### Just-in-time over just-in-case

Ways inject guidance when it's relevant, not preemptively. This keeps the context window lean and the guidance actionable. A 50-line testing way that appears when you run `pytest` is more effective than 50 lines permanently occupying the system prompt.

### Once per session

Most guidance only needs to be seen once. The marker system ensures a way fires on first match and stays silent afterward. This prevents the same guidance from consuming context on every prompt.

The exception is the context-threshold nag, which repeats deliberately because its purpose is enforcement, not education.

### Trigger specificity

Ways can trigger on user prompts (what you ask for), tool use (what Claude is about to do), or session state (how full the context is). This means guidance arrives through the channel closest to the action:

- Prompt triggers catch intent ("I want to refactor this")
- Command triggers catch execution (`git commit`)
- File triggers catch targets (editing `.env`)
- State triggers catch conditions (context 75% full)

### Separation from Claude Code

The system is built entirely on Claude Code's hook API - shell scripts that receive JSON and return JSON. No patches, no forks, no internal modifications. This means it survives Claude Code updates and can be shared across machines by copying `~/.claude/hooks/`.

## What This Replaces

Without this system, the alternatives are:

- **Giant CLAUDE.md files** - Everything in one file, always in context, diluting attention
- **Manual reminders** - Relying on the user to tell Claude about conventions
- **Post-hoc fixes** - Catching problems in code review instead of preventing them
- **Nothing** - Accepting inconsistency across sessions

The ways system is a middle ground: automated enough to be reliable, transparent enough to be understood, and lightweight enough to not get in the way.
