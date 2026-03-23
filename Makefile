# claude-code-config
# Top-level Makefile — canonical entry point for setup and maintenance.
#
# Quick start:   make setup
# Full install:  make install  (hooks + semantic matching + corpus)
# Update:        make update   (pull + setup)

.DEFAULT_GOAL := help
.PHONY: setup install update test test-all corpus clean help

# --- Primary targets ---

help:
	@echo "claude-code-config"
	@echo ""
	@echo "  make setup      Set up semantic matching (binary + model + corpus)"
	@echo "  make install    Full first-time setup (hooks + semantic matching)"
	@echo "  make update     Pull latest changes and re-run setup"
	@echo "  make test       Run embedding smoke tests"
	@echo "  make test-all   Run all tests (embedding + BM25 + integration)"
	@echo "  make clean      Remove build artifacts"
	@echo ""

# Set up the semantic matching engine + tools (embedding, mmaid, corpus).
# This is the most common target — run it after cloning or pulling.
setup:
	@echo "Setting up semantic matching engine..."
	$(MAKE) -C tools/way-embed setup
	@echo ""
	@echo "Setting up mmaid diagram renderer..."
	@bash tools/mmaid/download-mmaid.sh || echo "  (mmaid optional — skipping)"

# Full first-time install: make hooks executable, build way-match if needed, set up embeddings.
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

test-bm25:
	$(MAKE) -C tools/way-match test

test-integration:
	$(MAKE) -C tools/way-match test-integration

test-compare:
	bash tools/way-embed/compare-engines.sh

test-all: test test-bm25 test-integration

# --- Corpus ---

corpus:
	@bash tools/way-match/generate-corpus.sh --quiet

# --- Clean ---

clean:
	$(MAKE) -C tools/way-embed clean
	$(MAKE) -C tools/way-match clean
