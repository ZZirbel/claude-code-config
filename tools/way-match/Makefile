# way-match: BM25 semantic matcher for the ways system
# Build with Cosmopolitan for cross-platform APE binary,
# or with system compiler for local development.

COSMOCC ?= $(HOME)/.cosmocc/bin/cosmocc
CC      ?= cc
SRC      = tools/way-match/way-match.c
BIN      = bin/way-match

# Default: build with cosmocc for cross-platform APE binary
$(BIN): $(SRC) | bin
	$(COSMOCC) -O2 -o $@ $<

# Local development build with system compiler
local: $(SRC) | bin
	$(CC) -O2 -lm -o $(BIN) $<

bin:
	mkdir -p bin

# Build from source and compare against checked-in binary
verify: $(SRC)
	@mkdir -p /tmp
	$(COSMOCC) -O2 -o /tmp/way-match-verify $<
	@if cmp -s $(BIN) /tmp/way-match-verify; then \
		echo "PASS: binary matches source"; \
	else \
		echo "MISMATCH: checked-in binary differs from source build"; \
		echo "  checked-in:  $$(sha256sum $(BIN) 2>/dev/null || shasum -a 256 $(BIN))"; \
		echo "  from source: $$(sha256sum /tmp/way-match-verify 2>/dev/null || shasum -a 256 /tmp/way-match-verify)"; \
		exit 1; \
	fi
	@rm -f /tmp/way-match-verify

# Run test harness
test: $(BIN)
	bash tools/way-match/test-harness.sh --verbose

# Run test harness, BM25 only
test-bm25: $(BIN)
	bash tools/way-match/test-harness.sh --bm25-only --verbose

# Run NCD baseline only (no binary needed)
test-ncd:
	bash tools/way-match/test-harness.sh --ncd-only --verbose

clean:
	rm -f $(BIN)

.PHONY: local verify test test-bm25 test-ncd clean
