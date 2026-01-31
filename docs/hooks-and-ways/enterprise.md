# Enterprise Operating Model Ways

Guidance for enterprise platform tooling, work management, and knowledge systems.

## Domain Scope

This covers the patterns of enterprise work management and knowledge systems - not specific vendors, but the operating models they implement. Jira, Azure DevOps, Targetprocess, Confluence, SharePoint, and their competitors are instances of these patterns. The principles apply regardless of which tool is in play.

This matters because consulting work crosses organizational boundaries. Every client has a different toolchain but the underlying operating model patterns repeat.

## Principles

### Tools implement operating models, not the reverse

An organization's work management tool reflects (or should reflect) how they operate: their workflow states, approval gates, team boundaries, and reporting needs. When configuring or integrating with these tools, understand the operating model first. The tool is the implementation, not the source of truth.

### Work items are state machines

Every work management system, regardless of vendor, models work as items moving through states. The specifics differ (Jira calls them statuses, ADO calls them states, Targetprocess calls them entity states) but the pattern is universal: backlog → active → review → done, with variations. Understanding the state machine matters more than understanding the UI.

### Knowledge bases decay without curation

Confluence spaces, SharePoint sites, and wikis accumulate stale content over time. Search quality degrades. New team members can't find what they need. Curation is a continuous practice, not a one-time setup. When building or integrating with knowledge systems, consider the maintenance burden.

### Integration should be bidirectional and auditable

When connecting systems (work management to source control, knowledge base to CI/CD, etc.), data should flow both directions where it makes sense, and every change should be traceable to its source. A commit linked to a work item. A deployment linked to a release. The audit trail is the value.

---

## Ways

### work-management

**Principle**: Work management tools are state machines. Understand the operating model before the tool.

**Triggers on**: Mentioning Jira, Azure DevOps, Targetprocess, Linear, Asana, or work item management patterns.

**Guidance direction**: Map the workflow states before writing code or configuration. Understand required fields, transitions, and permissions. For integrations: use the tool's API, not screen scraping. For migrations: export, transform, validate, then import - never in-place. Respect the organization's workflow even if it seems suboptimal.

### knowledge-bases

**Principle**: Knowledge systems need structure and curation to remain useful.

**Triggers on**: Mentioning Confluence, SharePoint, wikis, knowledge management, or documentation platforms.

**Guidance direction**: Use space/site structure that mirrors organizational boundaries. Template pages for consistency. Label/tag systematically. For integrations: respect the hierarchy. For content creation: link to authoritative sources rather than duplicating. Archive rather than delete.

### planning

**Principle**: Planning artifacts should connect strategy to execution traceably.

**Triggers on**: Mentioning roadmaps, portfolio planning, program management, epics, or capacity planning.

**Guidance direction**: Hierarchy should be meaningful (epic → story → task reflects scope, not bureaucracy). Estimates are communication tools, not contracts. Dependencies between teams should be explicit and tracked. For reporting: measure flow (cycle time, throughput) not activity (hours logged).

### assessments

**Principle**: Assessments produce structured findings with evidence and recommendations.

**Triggers on**: Mentioning assessments, audits, maturity models, gap analysis, or readiness reviews.

**Guidance direction**: Use a consistent framework (capability, current state, target state, gap, recommendation). Score on a defined scale. Support every finding with evidence. Prioritize recommendations by impact and effort. Deliverable format: structured HTML/PDF with executive summary, detailed findings, and appendices.
