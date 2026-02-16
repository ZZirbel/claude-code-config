# way-match: BM25 semantic matcher for the ways system
# Build with Cosmopolitan for cross-platform APE binary,
# or with system compiler for local development.

COSMOCC  ?= $(HOME)/.cosmocc/bin/cosmocc
CC       ?= cc
SRCDIR    = tools/way-match
SNOWBALL  = $(SRCDIR)/snowball
SRC       = $(SRCDIR)/way-match.c
SNOW_SRC  = $(SNOWBALL)/api.c $(SNOWBALL)/utilities.c $(SNOWBALL)/stem_UTF_8_english.c
ALL_SRC   = $(SRC) $(SNOW_SRC)
BIN       = bin/way-match
CFLAGS    = -O2 -I$(SRCDIR)

# Default: build with cosmocc for cross-platform APE binary
$(BIN): $(ALL_SRC) | bin
	$(COSMOCC) $(CFLAGS) -o $@ $(ALL_SRC)

# Local development build with system compiler
local: $(ALL_SRC) | bin
	$(CC) $(CFLAGS) -lm -o $(BIN) $(ALL_SRC)

bin:
	mkdir -p bin

# Build from source and compare against checked-in binary
verify: $(ALL_SRC)
	@mkdir -p /tmp
	$(COSMOCC) $(CFLAGS) -o /tmp/way-match-verify $(ALL_SRC)
	@if cmp -s $(BIN) /tmp/way-match-verify; then \
		echo "PASS: binary matches source"; \
	else \
		echo "MISMATCH: checked-in binary differs from source build"; \
		echo "  checked-in:  $$(sha256sum $(BIN) 2>/dev/null || shasum -a 256 $(BIN))"; \
		echo "  from source: $$(sha256sum /tmp/way-match-verify 2>/dev/null || shasum -a 256 /tmp/way-match-verify)"; \
		exit 1; \
	fi
	@rm -f /tmp/way-match-verify

# Run test harness (comparative BM25 vs NCD)
test: $(BIN)
	bash tools/way-match/test-harness.sh --verbose

# Run integration test against real way files
test-integration: $(BIN)
	bash tools/way-match/test-integration.sh

# Run test harness, BM25 only
test-bm25: $(BIN)
	bash tools/way-match/test-harness.sh --bm25-only --verbose

# Run NCD baseline only (no binary needed)
test-ncd:
	bash tools/way-match/test-harness.sh --ncd-only --verbose

clean:
	rm -f $(BIN)

.PHONY: local verify test test-integration test-bm25 test-ncd clean
