# MCP Server Development Ways

Guidance for building Model Context Protocol servers.

## Domain Scope

This covers the design, implementation, and testing of MCP servers - the integration pattern for giving AI models structured access to external systems. The focus is on server-side development: tool design, semantic operation grouping, transport configuration, and testing patterns.

This is not about *using* MCP servers (that's just tool use). It's about *building* them.

## Principles

### Semantic operations over atomic CRUD

Don't expose raw create/read/update/delete operations. Group related actions into semantic operations that match how a user thinks about the task. "Manage a work item" is one operation with modes, not four separate tools. This reduces tool count, improves discoverability, and lets the model choose the right action from context.

The Obsidian MCP is the reference example: 20+ underlying operations consolidated into 5 semantic tools. Fewer tools means less decision overhead for the model, which means better tool selection.

### Entity-based architecture

Organize server code around the entities being managed (projects, repositories, work items, pages) not around HTTP verbs or API endpoints. Each entity module owns its schema, validation, and API mapping. This mirrors how the ADO MCP is structured and scales cleanly as capabilities grow.

### Workflow hints and state awareness

MCP servers should guide the model toward productive next steps. After a tool call succeeds, return contextual hints about what makes sense to do next. After a failure, return recovery suggestions. The server knows the domain better than the model does - encode that knowledge in the responses.

### Transport is a configuration concern, not an architecture one

HTTP, stdio, SSE - the transport layer should be swappable without changing tool logic. Design tools as pure functions that take input and return output. The transport wraps them.

---

## Ways

### server-design

**Principle**: MCP servers should present semantic operations, not raw API wrappers.

**Triggers on**: Mentioning MCP server development, tool design, or working in MCP server repositories.

**Guidance direction**: Start with the user's mental model of the domain, not the underlying API's structure. Group operations by entity. Design tool inputs for natural language usage (the model is generating the calls). Include descriptions that help the model choose the right tool. Return structured responses with next-step hints.

### semantic-operations

**Principle**: Consolidate related operations into fewer, smarter tools.

**Triggers on**: Designing MCP tools, discussing tool count, or mentioning semantic grouping.

**Guidance direction**: Each tool should handle a coherent slice of functionality with mode/action parameters rather than splitting into many atomic tools. Include JSON schema with clear descriptions for every parameter. Default optional parameters sensibly. The tool list is the model's menu - keep it readable.

### testing

**Principle**: MCP servers need testing at both the tool logic level and the integration level.

**Triggers on**: Writing tests for MCP servers or mentioning MCP testing.

**Guidance direction**: Unit test the tool handlers as pure functions (input → output). Integration test against the real API with fixtures. Test error paths - the model will send unexpected inputs. Test the hints/suggestions in responses. For transport testing, use stdio (simplest to automate).

### transport

**Principle**: Support multiple transports without coupling tool logic to any one.

**Triggers on**: Configuring MCP transport, mentioning stdio/HTTP/SSE, or discussing MCP server deployment.

**Guidance direction**: stdio for local development and testing. HTTP/SSE for remote deployment. The tool handler layer should be transport-agnostic. Configuration via environment variables or CLI flags, not hardcoded.
