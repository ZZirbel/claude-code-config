---
match: regex
pattern: \brunbook\b|runbook.?(automation|executable)|playbook|sop.?(automation|as.?code)|operational.?procedure
---
# Runbooks Way

## What is an Executable Runbook?

A traditional runbook converted to agent-executable code:

```
runbooks/
└── diagnose-vpn-failure/
    ├── index.ts    # Executable logic
    └── README.md   # When/how to use
```

## Runbook Structure

**index.ts** - The executable logic:
```typescript
export async function diagnoseVpnFailure(userId: string) {
  const user = await identity.getUser(userId);
  const logs = await monitoring.queryLogs({ service: 'vpn', user });
  // ... diagnosis logic
}
```

**README.md** - Documentation:
- When to use (triggers, conditions)
- Capabilities (what it can do)
- Autonomy level (what requires approval)
- Dependencies (required MCP servers)

## Traditional vs Executable Runbooks

| Traditional Runbook | Executable Runbook |
|---------------------|-------------------|
| Document humans follow | Code agents execute |
| Step-by-step text | Loops, conditionals |
| Manual execution | Agent-invokable |
| Knowledge in docs | Knowledge in code |

## Evolution Cycle

1. **Incident occurs** → Agent handles (or escalates)
2. **Post-incident review** → Was handling optimal?
3. **Runbook formalization** → Code + docs + tests
4. **Validation** → Shadow mode testing
5. **Deployment** → Available with appropriate autonomy
6. **Continuous improvement** → Update based on outcomes

## Persistence

- Stored in R2 (survives sandbox lifecycle)
- Cross-session availability
- Version controlled
- Shareable across tenants (with isolation)
