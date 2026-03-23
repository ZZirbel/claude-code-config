# way-embed: Embedding-based semantic matcher for the ways system
# Builds against llama.cpp (git submodule) via CMake.
#
# Per-platform native binaries. No cross-compilation — build on each target.
# Platform detection at setup time selects the right binary.

BUILDDIR  = build
BIN       = ../../bin/way-embed
CMAKE_FLAGS = -DCMAKE_BUILD_TYPE=Release

# Platform detection
OS    := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH  := $(shell uname -m)
PLATFORM = $(OS)-$(ARCH)

# Platform-tagged binary (e.g., way-embed-linux-x86_64)
PLATFORM_BIN = ../../bin/way-embed-$(PLATFORM)

# Default: build for this platform and install as way-embed
$(BIN): cmake-build
	cp $(BUILDDIR)/way-embed $(PLATFORM_BIN)
	cp $(PLATFORM_BIN) $(BIN)
	@echo ""
	@echo "Built: $(PLATFORM_BIN) ($$(ls -lh $(PLATFORM_BIN) | awk '{print $$5}'))"

cmake-build: CMakeLists.txt way-embed.cpp | llama.cpp/CMakeLists.txt
	@mkdir -p $(BUILDDIR)
	@cd $(BUILDDIR) && cmake $(CMAKE_FLAGS) .. 2>&1 | tail -5
	cmake --build $(BUILDDIR) --target way-embed -j$$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# Ensure submodule is initialized
llama.cpp/CMakeLists.txt:
	@echo "Initializing llama.cpp submodule..."
	git -C ../.. submodule update --init --depth 1 tools/way-embed/llama.cpp

# Build from source and compare against checked-in binary
verify: cmake-build
	@if cmp -s $(PLATFORM_BIN) $(BUILDDIR)/way-embed; then \
		echo "PASS: binary matches source ($(PLATFORM))"; \
	else \
		echo "MISMATCH: checked-in binary differs from source build"; \
		exit 1; \
	fi

# Model download (XDG cache location)
MODEL_DIR  = $(shell echo $${XDG_CACHE_HOME:-$$HOME/.cache})/claude-ways/user
MODEL      = $(MODEL_DIR)/minilm-l6-v2.gguf
SRCDIR     = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

model: $(MODEL)
$(MODEL):
	bash $(SRCDIR)download-model.sh

# Download directly from HuggingFace (for provenance verification)
model-upstream:
	bash $(SRCDIR)download-model.sh --upstream

# Full setup: build binary, download model, regenerate corpus with embeddings
setup: $(BIN) $(MODEL)
	@echo "Regenerating corpus with embeddings..."
	bash $(SRCDIR)../../tools/way-match/generate-corpus.sh
	@echo ""
	@echo "Setup complete. Running verification..."
	bash $(SRCDIR)test-embedding.sh
	@echo ""
	@echo "To compare against BM25: bash $(SRCDIR)compare-engines.sh"

# Run basic smoke test
test: $(BIN)
	@echo "Testing way-embed ($(PLATFORM))..."
	$(BIN) --version
	@echo "PASS: version check"

# Publish pre-built binaries + model to GitHub Releases
# Run on each platform, then create release with all artifacts.
# Usage: make release VERSION=v0.1.0
VERSION ?= v0.1.0
RELEASE_TAG = way-embed-$(VERSION)
GH_REPO = $(shell git -C ../.. remote get-url origin | sed 's|.*github.com[:/]||;s|\.git$$||')

# Build and tag the platform binary for release
release-build: $(PLATFORM_BIN)
	@echo "Built $(PLATFORM_BIN) for release"
	@ls -lh $(PLATFORM_BIN)

# Expected platform binaries for release
RELEASE_PLATFORMS = linux-x86_64 linux-aarch64 darwin-x86_64 darwin-arm64
RELEASE_BINS = $(addprefix ../../bin/way-embed-,$(RELEASE_PLATFORMS))

# Create the release (run after CI builds all platforms)
release:
	@echo "Publishing $(RELEASE_TAG) to $(GH_REPO)..."
	@echo "Expected binaries:"; for b in $(RELEASE_BINS); do \
		[ -f "$$b" ] && ls -lh "$$b" || echo "  MISSING: $$b"; \
	done
	gh release create $(RELEASE_TAG) \
		--repo $(GH_REPO) \
		--title "way-embed $(VERSION)" \
		--notes-file $(SRCDIR)RELEASE.md \
		$(wildcard $(RELEASE_BINS)) $(MODEL)
	@echo "Published: https://github.com/$(GH_REPO)/releases/tag/$(RELEASE_TAG)"

clean:
	rm -rf $(BUILDDIR)

.PHONY: cmake-build verify test model model-upstream setup release-build release clean
