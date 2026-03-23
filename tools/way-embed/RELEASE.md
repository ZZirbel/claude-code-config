Pre-built binaries and model for ADR-108 embedding-based way matching.

## Quick Install

```bash
# Detect your platform
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"

# Download platform binary + model
gh release download way-embed-v0.1.0 \
  -p "way-embed-${PLATFORM}" -D ~/.claude/bin/
cp ~/.claude/bin/way-embed-${PLATFORM} ~/.claude/bin/way-embed
chmod +x ~/.claude/bin/way-embed

gh release download way-embed-v0.1.0 -p 'minilm-l6-v2.gguf' \
  -D "${XDG_CACHE_HOME:-~/.cache}/claude-ways/user/"

# Regenerate corpus with embeddings
bash ~/.claude/tools/way-match/generate-corpus.sh

# Verify
bash ~/.claude/tools/way-embed/test-embedding.sh
```

## Available platforms

| Binary | Platform |
|--------|----------|
| `way-embed-linux-x86_64` | Linux x86_64 |
| `way-embed-linux-aarch64` | Linux ARM64 |
| `way-embed-darwin-x86_64` | macOS Intel |
| `way-embed-darwin-arm64` | macOS Apple Silicon |

## Build from source

If your platform isn't listed:

```bash
cd ~/.claude/tools/way-embed && make setup
```

Requires: cmake, C++ compiler, git (for submodule).

## Verify model provenance

Download the model directly from HuggingFace instead of the release:

```bash
bash ~/.claude/tools/way-embed/download-model.sh --upstream
```

Both paths verify against the same SHA-256 checksum.

## Switch engines

Set `"semantic_engine"` in `~/.claude/ways.json`:
- `"auto"` — embedding if available, falls back to BM25 (default)
- `"embedding"` — force embedding engine
- `"bm25"` — force BM25 engine

## Compare engines

```bash
bash ~/.claude/tools/way-embed/compare-engines.sh
```
