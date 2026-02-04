---
match: semantic
description: application security, authentication, secrets management, input validation, vulnerability prevention
vocabulary: authentication secrets password credentials owasp injection xss sql sanitize vulnerability
threshold: 0.52
scope: agent, subagent
---
# Security Way

## Never Commit

- `.env` files with real secrets
- API keys, tokens, passwords
- Private keys, certificates

When creating `.env`, also create `.env.example` with placeholder values. Verify `.env` is in `.gitignore`.

## Detection and Action Rules

When writing or reviewing code, actively check for:

| If You See | Do This |
|------------|---------|
| String concatenation in SQL | Replace with parameterized queries |
| `innerHTML` with user input | Use `textContent` or sanitize |
| Password stored in plain text | Hash with bcrypt or argon2 |
| Hardcoded secret in source | Extract to environment variable, flag it |
| Missing auth check on endpoint | Add middleware/guard, flag it |
| User input in shell command | Use parameterized execution, never string interpolation |

## When Reviewing Existing Code

Flag these as security issues:
- Hardcoded secrets or credentials
- SQL string concatenation
- Unsanitized user input in templates or commands
- Missing authentication/authorization on endpoints
- Sensitive data in logs

## Defaults

- Parameterized queries for all database access
- Escape output for its context (HTML, URL, SQL)
- Validate at system boundaries (user input, external APIs)
- Principle of least privilege for permissions
