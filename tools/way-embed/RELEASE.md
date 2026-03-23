Pre-built binary and model for ADR-108 embedding-based way matching.

## Quick Install

```bash
# Download binary
gh release download way-embed-v0.1.0 -p 'way-embed' -D ~/.claude/bin/
chmod +x ~/.claude/bin/way-embed

# Download model (21MB Q5_K_M)
gh release download way-embed-v0.1.0 -p 'minilm-l6-v2.gguf' \
  -D "${XDG_CACHE_HOME:-~/.cache}/claude-ways/user/"

# Regenerate corpus with embeddings
bash ~/.claude/tools/way-match/generate-corpus.sh

# Verify
bash ~/.claude/tools/way-embed/test-embedding.sh
```

## Verify model provenance

If you prefer to download the model directly from the publisher:

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
