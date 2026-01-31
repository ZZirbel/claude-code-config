# Research Ways

Guidance for web research, report assembly, and data collection.

## Domain Scope

This covers the research-oriented work pattern: gathering information from multiple sources, synthesizing it into structured outputs, and producing deliverables (HTML reports, PDFs, datasets). This is distinct from software development - the output is knowledge artifacts, not running code.

## Principles

### Research is iterative, not linear

You rarely know the full shape of a topic before you start. The process is: broad search → identify themes → targeted deep dives → synthesis. Don't try to write the final report on the first pass.

### Sources matter

Track where information comes from. Not just for citation - for credibility assessment. A vendor's blog post about their own product is different from an independent benchmark. Primary sources over secondary. Recent over dated.

### Output format serves the audience

HTML reports that render to PDF are the default deliverable format. They need to be self-contained (inline styles, no external dependencies), readable in a browser, and printable. Data-heavy findings may warrant SQLite databases or structured datasets alongside the narrative.

### Separate data collection from analysis

Gathering raw data (web content, API responses, measurements) is a different step from interpreting it. Store the raw data first, analyze second. This makes the analysis reproducible and the data reusable.

---

## Ways

### gathering

**Principle**: Web research should be systematic, not ad-hoc browsing.

**Triggers on**: Using WebSearch/WebFetch tools extensively, or mentioning research/investigation/survey.

**Guidance direction**: Start with broad queries to map the landscape. Track sources with URLs and access dates. Save raw content before summarizing (summaries lose detail). When hitting paywalls or access restrictions, note them rather than working around them. Rate-limit requests to be a good citizen.

### reports

**Principle**: Reports are self-contained HTML documents that render cleanly to PDF.

**Triggers on**: Mentioning report generation, HTML output, or PDF assembly.

**Guidance direction**: Use semantic HTML (sections, headings, figures, tables). Inline all styles - no external CSS or assets. Include a title page with date, author, and scope. Use print media queries for PDF rendering (`@media print`). Table of contents for anything over 3 sections. Charts and visualizations should be SVG (scalable, inline-able).

### datasets

**Principle**: Structured data outputs should be queryable and portable.

**Triggers on**: Mentioning SQLite, data collection, dataset construction, or graph data.

**Guidance direction**: SQLite is the default for tabular data (zero-dependency, queryable, portable). Include a schema description and provenance metadata (where the data came from, when, what transformations were applied). For graph data, use standard formats (GraphML, JSON-LD, or SQLite with edge tables). Always include a data dictionary.

### citations

**Principle**: Track provenance for all externally-sourced information.

**Triggers on**: Mentioning sources, citations, references, or bibliography.

**Guidance direction**: Record URL, access date, title, and author/publisher for every source. Use a consistent format. Group by primary/secondary/tertiary. Flag sources that may have bias (vendor content, sponsored research). Include the citation list in the deliverable.
