---
status: Accepted
date: 2026-03-30
deciders:
  - aaronsb
  - claude
related:
  - ADR-014
  - ADR-107
  - ADR-108
  - ADR-110
---

# ADR-111: Unified `ways` CLI — Single Binary Tool Consolidation

## Context

The ways tooling has grown organically across multiple languages and entry points:

| Tool | Language | Lines | Function |
|------|----------|-------|----------|
| `way-match` | C | ~920 | BM25 scoring |
| `way-embed` | C++ | ~920 | Embedding match (ONNX/GGUF) |
| `generate-corpus.sh` | Bash | ~200 | Corpus generation |
| `lint-ways.sh` | Bash | ~530 | Frontmatter validation |
| `way-tree-analyze.sh` | Bash | ~300 | Tree structure analysis |
| `embed-lib.sh` | Bash | ~200 | Shared utilities |
| `embed-suggest.sh` | Bash | ~100 | Embedding suggestions |
| `provenance-scan.py` | Python | ~150 | Provenance scanning |
| `governance.sh` | Bash | ~540 | Governance orchestration |
| Various others | Bash | ~500 | Misc utilities |

Every tool re-walks the same directory tree and re-parses the same frontmatter. Adding a new feature (e.g., the graph generator from ADR-110) means writing yet another script that duplicates file discovery, YAML extraction, and JSON emission. The bash scripts also carry macOS bash 3.2 compatibility constraints that a compiled binary eliminates.

The `gh` CLI, `aws` CLI, and `gcloud` CLI demonstrate the pattern: one binary, subcommands for everything, shared infrastructure for common operations.

## Decision

### 1. Create a `ways` CLI binary

A single `ways` binary replaces all current tooling with subcommands:

```
ways lint [path]           # frontmatter validation (lint-ways.sh)
ways corpus [--global]     # corpus generation (generate-corpus.sh)
ways match <query>         # BM25 scoring (way-match)
ways embed <query>         # embedding match (way-embed)
ways siblings <id>         # way-vs-way cosine scoring (new, ADR-110 §5)
ways graph [--format jsonl]# graph export (new, ADR-110 §4)
ways tree <path>           # tree analysis (way-tree-analyze.sh)
ways provenance            # provenance scanning (provenance-scan.py)
```

### 2. Rust for the CLI, existing C/C++ via `cc` crate

The CLI shell, file walking, YAML parsing, JSON emission, and all "script replacement" logic is written in Rust. The existing C (`way-match.c`) and C++ (`way-embed.cpp`) are compiled into the binary via the `cc` build crate and called through thin FFI wrappers.

Rationale: the inference code (BM25 tokenization, ONNX runtime, GGUF model loading) is numerics-sensitive, already tested across 4 platforms, and rarely changes. The script logic being replaced is 90% string processing and file I/O — Rust's strengths.

### 3. Project structure

```
tools/ways-cli/
├── Cargo.toml
├── build.rs                 # cc::Build compiles csrc/
├── src/
│   ├── main.rs              # clap dispatcher
│   ├── cmd/
│   │   ├── lint.rs          # frontmatter validation
│   │   ├── corpus.rs        # corpus generation
│   │   ├── match_bm25.rs    # FFI wrapper → way-match.c
│   │   ├── embed.rs         # FFI wrapper → way-embed.cpp
│   │   ├── siblings.rs      # FFI wrapper → way-embed.cpp
│   │   ├── graph.rs         # JSONL graph export
│   │   ├── tree.rs          # tree analysis
│   │   └── provenance.rs    # provenance scanning
│   ├── scanner.rs           # shared: file discovery by frontmatter
│   ├── frontmatter.rs       # shared: YAML frontmatter parsing
│   └── ffi.rs               # extern "C" declarations for C/C++
├── csrc/
│   ├── way-match.c          # existing BM25 (from tools/way-match/)
│   ├── way-embed.cpp        # existing embedding (from tools/way-embed/)
│   ├── stem_UTF_8_english.c # Snowball stemmer
│   └── *.h                  # headers
└── tests/
```

### 4. Incremental delivery

Subcommands ship independently. The order follows dependency:

| Phase | Subcommands | Replaces | C/C++ needed |
|-------|-------------|----------|--------------|
| 1 | `lint`, `corpus`, `graph` | lint-ways.sh, generate-corpus.sh, new | No |
| 2 | `match`, `embed`, `siblings` | way-match, way-embed, new | Yes (FFI) |
| 3 | `tree`, `provenance` | way-tree-analyze.sh, provenance-scan.py | No |

Phase 1 is pure Rust — no FFI, no ONNX dependency. It validates the build pipeline and CLI ergonomics. Phase 2 introduces the FFI boundary. Phase 3 ports the remaining utilities.

### 5. Installation and path

The binary installs to `~/.claude/bin/ways`. The hook scripts (`show-way.sh`, `check-prompt.sh`, etc.) call `ways` subcommands instead of individual tools. During the transition, both old and new tools coexist — hooks detect which is available and prefer `ways` when present.

### 6. Path to pure Rust (optional, not required)

The FFI boundary is thin and the C/C++ is stable. However, the architecture does not prevent porting:

- `way-match.c` → pure Rust BM25 (mechanical port, ~500 lines)
- `way-embed.cpp` → `ort` crate for ONNX + Rust GGUF loader (larger effort, evaluate when `ort` static linking matures)

This is a future choice, not a commitment. The FFI approach is the long-term default unless there's a reason to change.

## Consequences

### Positive

- Single binary, single install, single update path
- Shared file scanning — one tree walk serves all subcommands
- Shared frontmatter parsing — one YAML parser, tested once
- New features (graph, siblings) are subcommands, not new scripts
- macOS bash 3.2 compatibility concerns eliminated for ported logic
- `ways --help` gives discoverability across all tooling
- Shell completion for free via `clap`

### Negative

- Rust toolchain required for development (not for end users — binary is distributed)
- FFI boundary between Rust and C/C++ is a maintenance surface (mitigated: it's thin and the C/C++ is stable)
- CI must cross-compile Rust + C/C++ for 4 platforms (mitigated: `cargo-zigbuild` handles this)
- Porting bash logic to Rust takes more lines for the same functionality (mitigated: the logic is straightforward and the type system catches bugs the bash scripts silently swallow)

### Neutral

- The existing bash scripts remain in the repo during transition but are progressively replaced. Once all hooks prefer `ways`, the scripts can be removed
- `governance.sh` becomes a thin orchestrator calling `ways provenance` + `ways lint` instead of calling scripts directly — or itself becomes `ways governance`
- The `Makefile` gains a `make ways` target; `make install` includes the `ways` binary
- CI builds change from "compile C, compile C++, run bash" to "cargo build, run tests"

## Alternatives Considered

### Pure Go

Go's `cobra` library is excellent for CLIs and cross-compilation is normally trivial. However, ONNX Runtime is a C library — Go requires CGo to call it. CGo cross-compilation for 4 platforms requires Docker-based toolchains or zig-cc as a C cross-compiler, negating Go's primary advantage. The CGo boundary is also more awkward than Rust's `cc` crate integration.

### Pure Rust (rewrite everything)

Porting the C/C++ inference code to Rust risks subtle behavioral differences in numerics-sensitive paths (BM25 scoring, embedding normalization). The `ort` crate for ONNX is solid but static linking of ONNX Runtime remains uneven across platforms. The incremental approach (Rust shell + C/C++ FFI) gets to a working binary faster and keeps the option open.

### Extend C++

C++ is the right language for the inference engine but the wrong language for directory walking, YAML parsing, CLI dispatch, and JSON emission — which is 80% of the work. Libraries like `yaml-cpp` and `CLI11` exist but are a step down from `serde_yaml` and `clap`. The bash scripts exist precisely because C++ was too high-friction for the scripting layer.

### Go + C/C++ library (CGo)

Same FFI benefit as Rust + `cc`, but CGo cross-compilation is harder than Rust's `cargo-zigbuild`, and maintaining three languages (Go + C + C++) is worse than two (Rust + C/C++).

## Interaction with Other ADRs

| ADR | Interaction |
|-----|-------------|
| ADR-014 | `way-match` binary becomes `ways match` subcommand. BM25 algorithm unchanged |
| ADR-107 | Corpus generation becomes `ways corpus`. Locale support (Phase 3) becomes a flag |
| ADR-108 | `way-embed` binary becomes `ways embed` subcommand. ONNX/GGUF loading unchanged |
| ADR-110 | Graph export (`ways graph`) and sibling scoring (`ways siblings`) ship as subcommands rather than standalone scripts |
