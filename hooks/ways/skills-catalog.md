# Skills Catalog

Curated index of official and vetted skills. Ways reference these — they don't duplicate them.

**Install official skills:** `/plugin marketplace add anthropics/skills` then `/plugin install <plugin-name>@anthropic-agent-skills`

## Official Anthropic Skills ([anthropics/skills](https://github.com/anthropics/skills))

### Document Creation (source-available, proprietary license)

| Skill | Triggers on | What it does |
|-------|-------------|--------------|
| **pptx** | .pptx, slides, deck, presentation | Create/edit/read PowerPoint files. Uses pptxgenjs for creation, markitdown for reading |
| **docx** | .docx, Word document | Create/edit/read Word documents |
| **pdf** | .pdf, PDF | Read, extract, create PDF files |
| **xlsx** | .xlsx, spreadsheet | Create/edit spreadsheets with formulas and charts |

### Content & Writing (Apache 2.0)

| Skill | Triggers on | What it does |
|-------|-------------|--------------|
| **doc-coauthoring** | write docs, draft proposal, create spec, RFC | 3-stage workflow: context gathering → refinement → reader testing |
| **internal-comms** | status report, 3P update, newsletter, FAQ | Templates for internal communications formats |

### Design & Creative (Apache 2.0)

| Skill | Triggers on | What it does |
|-------|-------------|--------------|
| **canvas-design** | visual art, .png, design | Create visual art in PNG/PDF using design philosophy |
| **algorithmic-art** | algorithmic art, p5.js, generative | p5.js with seeded randomness and interactive parameters |
| **brand-guidelines** | brand colors, typography, Anthropic brand | Anthropic's official brand identity and styling |
| **theme-factory** | theme, styling artifacts | Style artifacts (slides, docs, reports, HTML) with themes |
| **slack-gif-creator** | GIF for Slack, animated GIF | Animated GIFs optimized for Slack constraints |
| **frontend-design** | web UI, frontend, interface | Production-grade frontend interfaces. *Already in our skills* |

### Development (Apache 2.0)

| Skill | Triggers on | What it does |
|-------|-------------|--------------|
| **claude-api** | anthropic SDK, Claude API | Build apps with Claude API. *Already in our skills* |
| **mcp-builder** | MCP server, Model Context Protocol | Guide for creating MCP servers |
| **webapp-testing** | test web app, Playwright | Test local web apps using Playwright |
| **web-artifacts-builder** | HTML artifact, web artifact | Multi-component claude.ai HTML artifacts |
| **skill-creator** | create skill, modify skill | Create/improve skills and measure performance |

## Official Plugins ([anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official))

### Development Workflow

code-review, code-simplifier, commit-commands, feature-dev, pr-review-toolkit, plugin-dev, mcp-server-dev, agent-sdk-dev, claude-code-setup, claude-md-management, hookify, playground

### LSP Servers

clangd, csharp, gopls, jdtls (Java), kotlin, lua, php, pyright, ruby, rust-analyzer, swift, typescript

### Output Styles

explanatory-output-style, learning-output-style

### Other

math-olympiad, ralph-loop, security-guidance, skill-creator

### External/Partner Plugins

asana, context7, discord, fakechat, firebase, github, gitlab, greptile, laravel-boost, linear, playwright, serena, slack, supabase, telegram

## Gap Analysis: What Ways Would Add

Skills are procedures — they tell Claude *how* to do something. Ways are judgment — they tell Claude *when* and *why*.

| Domain | Skills exist | Way would add |
|--------|-------------|---------------|
| **Writing** | doc-coauthoring, internal-comms, docx | When to use which format, audience analysis, tone calibration, when to co-author vs just write |
| **Research** | (none) | Structured investigation, source evaluation, synthesis, comparative analysis |
| **Presentation** | pptx, theme-factory | Narrative arc, slide structure decisions, when slides vs docs vs diagrams |
| **Data/Analysis** | xlsx | When to use spreadsheets vs charts vs tables, data storytelling |
| **Creative** | algorithmic-art, canvas-design, slack-gif-creator | (sparse — creative work is hard to systematize into ways) |

### Proposed Way Domains

**`writing/`** — Fire on content creation prompts. Reference official skills for execution.
- `writing/draft` → points to doc-coauthoring skill for structured docs
- `writing/presentation` → points to pptx + theme-factory skills
- `writing/report` → points to docx/pdf skills, adds structure guidance
- `writing/edit` → revision and tone guidance (no skill equivalent)

**`research/`** — No official skills exist here. This is greenfield.
- `research/explore` → structured investigation methodology
- `research/compare` → comparative analysis, decision matrices
- `research/summarize` → distillation patterns
- `research/sources` → citation and verification protocol
