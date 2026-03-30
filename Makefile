# claude-code-config
# Top-level Makefile — canonical entry point for setup and maintenance.
#
# Quick start:   make setup
# Full install:  make install  (hooks + ways CLI + embedding + corpus)
# Update:        make update   (pull + setup)

.DEFAULT_GOAL := help
.PHONY: setup install update test test-all corpus lint clean help ways

WAYS_BIN = bin/ways

# --- Primary targets ---

help:
	@echo "claude-code-config"
	@echo ""
	@echo "  make setup      Set up ways CLI + embedding engine + corpus"
	@echo "  make install    Full first-time setup (hooks + tools + corpus)"
	@echo "  make update     Pull latest changes and re-run setup"
	@echo "  make test       Run embedding smoke tests"
	@echo "  make test-all   Run all tests (embedding + BM25)"
	@echo "  make corpus     Regenerate the ways corpus"
	@echo "  make lint       Lint all way frontmatter"
	@echo "  make ways       Build the ways CLI (Rust)"
	@echo "  make clean      Remove build artifacts"
	@echo ""

# Set up the ways CLI, embedding engine, and corpus.
# This is the most common target — run it after cloning or pulling.
setup: ways
	@echo "Setting up embedding engine..."
	$(MAKE) -C tools/way-embed setup
	@echo ""
	@echo "Setting up mmaid diagram renderer..."
	@bash tools/mmaid/download-mmaid.sh || echo "  (mmaid optional — skipping)"
	@echo ""
	@echo "Regenerating corpus..."
	$(WAYS_BIN) corpus --quiet

# Full first-time install.
install: hooks-executable setup
	@echo ""
	@echo "Install complete. Restart Claude Code for ways to take effect."
	@echo "  Review hooks at: ~/.claude/hooks/"

# Pull upstream changes and re-run setup.
update:
	@echo "Pulling latest changes..."
	git pull --ff-only
	@echo ""
	$(MAKE) install

# --- Supporting targets ---

hooks-executable:
	@find hooks -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
	@echo "Hooks marked executable."

# --- Tests ---

test: corpus
	bash tools/way-embed/test-embedding.sh

test-bm25: ways corpus
	@echo "Testing BM25 via ways match..."
	$(WAYS_BIN) match "write a unit test" >/dev/null && echo "  PASS: match returned results" || echo "  FAIL: no match results"
	$(WAYS_BIN) match "configure ssh remote server" >/dev/null && echo "  PASS: match returned results" || echo "  FAIL: no match results"

test-compare:
	bash tools/way-embed/compare-engines.sh

test-all: test test-bm25

# --- Corpus & Lint ---

corpus: ways
	@$(WAYS_BIN) corpus --quiet

lint: ways
	@$(WAYS_BIN) lint

# --- Ways CLI ---

ways:
	@if [ ! -x $(WAYS_BIN) ] || [ tools/ways-cli/src/main.rs -nt $(WAYS_BIN) ]; then \
		cargo build --release --manifest-path tools/ways-cli/Cargo.toml; \
		mkdir -p bin; \
		cp tools/ways-cli/target/release/ways $(WAYS_BIN); \
		echo "Built: $(WAYS_BIN)"; \
	fi

# --- Clean ---

clean:
	$(MAKE) -C tools/way-embed clean
	cargo clean --manifest-path tools/ways-cli/Cargo.toml 2>/dev/null || true
