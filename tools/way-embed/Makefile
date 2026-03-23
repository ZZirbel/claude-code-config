# way-embed: Embedding-based semantic matcher for the ways system
# Builds against llama.cpp (git submodule) via CMake.

BUILDDIR  = build
BIN       = ../../bin/way-embed
COSMOCC  ?= $(HOME)/.cosmocc/bin/cosmocc
COSMOCXX ?= $(HOME)/.cosmocc/bin/cosmoc++
CMAKE_FLAGS = -DCMAKE_BUILD_TYPE=Release

# Default: build with system compiler
$(BIN): cmake-build
	cp $(BUILDDIR)/way-embed $@

cmake-build: CMakeLists.txt way-embed.cpp | llama.cpp/CMakeLists.txt
	@mkdir -p $(BUILDDIR)
	@cd $(BUILDDIR) && cmake $(CMAKE_FLAGS) .. 2>&1 | tail -5
	@cmake --build $(BUILDDIR) --target way-embed -j$$(nproc 2>/dev/null || echo 4) 2>&1 | tail -10

# Build with Cosmopolitan (cross-platform APE) — experimental
cosmo: CMakeLists.txt way-embed.cpp | llama.cpp/CMakeLists.txt
	@mkdir -p $(BUILDDIR)-cosmo
	@cd $(BUILDDIR)-cosmo && cmake $(CMAKE_FLAGS) \
		-DCMAKE_C_COMPILER=$(COSMOCC) \
		-DCMAKE_CXX_COMPILER=$(COSMOCXX) \
		-DCMAKE_SYSTEM_NAME=Generic \
		.. 2>&1 | tail -5
	@cmake --build $(BUILDDIR)-cosmo --target way-embed -j$$(nproc 2>/dev/null || echo 4) 2>&1 | tail -10
	cp $(BUILDDIR)-cosmo/way-embed $(BIN)

# Ensure submodule is initialized
llama.cpp/CMakeLists.txt:
	@echo "Initializing llama.cpp submodule..."
	git -C ../.. submodule update --init --depth 1 tools/way-embed/llama.cpp

# Build from source and compare against checked-in binary
verify: cmake-build
	@if cmp -s $(BIN) $(BUILDDIR)/way-embed; then \
		echo "PASS: binary matches source"; \
	else \
		echo "MISMATCH: checked-in binary differs from source build"; \
		exit 1; \
	fi

# Model download (XDG cache location)
MODEL_DIR  = $(shell echo $${XDG_CACHE_HOME:-$$HOME/.cache})/claude-ways/user
MODEL      = $(MODEL_DIR)/minilm-l6-v2-f16.gguf
SRCDIR     = $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

model: $(MODEL)
$(MODEL):
	bash $(SRCDIR)download-model.sh

# Download directly from HuggingFace (for provenance verification)
model-upstream:
	bash $(SRCDIR)download-model.sh --upstream

# Run basic smoke test
test: $(BIN)
	@echo "Testing way-embed..."
	$(BIN) --version
	@echo "PASS: version check"

clean:
	rm -rf $(BUILDDIR) $(BUILDDIR)-cosmo

.PHONY: cmake-build cosmo verify test model model-upstream clean
