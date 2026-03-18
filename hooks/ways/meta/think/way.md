---
description: structured reasoning, thinking frameworks, cognitive scaffolding for complex decisions
vocabulary: explore options approaches trade-off balance alternatives stuck principle abstract reasoning framework systematic
threshold: 2.0
scope: agent, subagent
---
# Structured Thinking

When you encounter complexity, don't reach for a framework first. Evaluate whether you need one.

## The Metacognitive Check

Before solving, pause and assess: **is your understanding trending toward clarity or away from it?**

Do not attempt to solve in this first cycle. Just evaluate the direction:

1. **Trending clear** — You can see the shape of the answer. Proceed normally. No scaffolding needed.
2. **Trending unclear** — The problem has competing concerns, hidden dependencies, or you're uncertain which direction to go. Escalate.

## Escalation Gradient

| Level | What happens | When |
|---|---|---|
| **Internal reasoning** | Think harder silently — extend your reasoning, consider more angles | Unclear but likely resolvable with more thought |
| **External strategy** | Use a structured strategy (below) — surfaces your reasoning step-by-step | Internal reasoning isn't converging; the human should see the work |
| **Collaborative** | Discuss with the human — they have context you lack | Strategy hits unknowns that tools can't resolve |

Most problems resolve at level 1. The strategies exist for when they don't.

You don't have to wait for human input to begin an external strategy. But if during your reasoning steps you encounter unknowns that can't be resolved through your tools, the remaining resource is the human. Ask.

## External Strategies

When you escalate to an external strategy, select based on problem shape and invoke the skill:

| Problem Shape | Strategy | Invoke |
|---|---|---|
| Multiple viable approaches | Tree of Thoughts | `/think-tree` |
| Three competing objectives | Trilemma | `/think-trilemma` |
| High-stakes, need confidence | Self-Consistency | `/think-consistency` |
| Stuck, need first principles | Step-Back | `/think-stepback` |
| Investigation or debugging | ReAct | `/think-react` |

Each strategy is a step-by-step scaffold. The skill tracks progress through stages — follow them in order.
