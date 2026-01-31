# AI / Agent Development Ways

Guidance for working with language models, building agent systems, and evaluating AI tooling.

## Domain Scope

This covers the practice of working with AI as a medium: building agent systems, evaluating models, designing prompts, and running local models. It's meta in a sense - we're using Claude to build things that use models - but the principles are about the craft, not the specific tool.

## Principles

### Models are capabilities, not magic

A model has a context window, a knowledge cutoff, strengths, and weaknesses. Designing around these constraints produces better results than hoping the model figures it out. Know what the model is good at (synthesis, pattern matching, generation) and what it's bad at (precise counting, long-range consistency, factual recall of obscure details).

### Agents are loops with judgment

An agent is a model in a loop that can use tools and make decisions. The quality of the agent depends on: the clarity of its instructions, the quality of its tools, and the feedback it gets from the environment. Fancy architectures don't compensate for bad tools or vague instructions.

### Evaluation is the bottleneck

Building an AI feature is fast. Knowing whether it works well is hard. Evaluation should be designed before implementation, not after. "How will we know this is good?" is the first question, not the last.

### Local models serve different purposes

Local models (Ollama, llama.cpp, etc.) aren't cheaper versions of cloud models. They're different tools: private by default, latency-predictable, and unconstrained by API rate limits. They're best for tasks where privacy matters, latency consistency matters, or the task is well-scoped enough that a smaller model suffices.

---

## Ways

### agents

**Principle**: Agent systems should have clear instruction boundaries, good tools, and observable behavior.

**Triggers on**: Mentioning agent design, agentic loops, tool use patterns, or multi-step AI workflows.

**Guidance direction**: Define the agent's scope explicitly (what it can do, what it should refuse). Design tools to return structured output the model can reason about. Include observation points - log what the agent decided and why. Set iteration limits. For multi-agent systems: clear handoff protocols and shared state management.

### evaluation

**Principle**: Design evaluation criteria before building the feature.

**Triggers on**: Mentioning AI evaluation, benchmarks, quality assessment, or testing AI outputs.

**Guidance direction**: Define success criteria in measurable terms. Use rubrics for subjective quality. Test at multiple levels: unit (does the prompt produce the right format?), integration (does the tool chain work end-to-end?), and acceptance (does the user get value?). Track regressions - model updates can change behavior.

### prompting

**Principle**: Prompts are software. They should be version-controlled, tested, and iterated.

**Triggers on**: Designing prompts, mentioning prompt engineering, or working with system prompts.

**Guidance direction**: Separate instructions from examples from context. Be specific about output format. Use constraints ("do not...", "always...") for critical behaviors. Test with adversarial inputs. For long prompts: structure with headers, use XML tags for boundaries. Version control prompts alongside the code that uses them.

### local-models

**Principle**: Local models are tools with specific strengths, not universal replacements.

**Triggers on**: Mentioning Ollama, llama.cpp, local inference, self-hosted models, or model quantization.

**Guidance direction**: Match model size to task. Quantization trades quality for speed/memory - understand the trade-off for your use case. For classification and extraction tasks, smaller models often suffice. For generation and reasoning, larger models matter more. GPU memory is the primary constraint - check before downloading.
