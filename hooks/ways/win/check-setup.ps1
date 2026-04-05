#Requires -Version 5.1
# SessionStart: Check if ways installation is complete.
# Runs as the first startup hook. If setup is incomplete, emits a
# one-time diagnostic and exits cleanly so other hooks don't error.
#
# Checks: ways binary -> embedding model (optional) -> corpus

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$waysBin = Join-Path $env:USERPROFILE ".claude\bin\ways.exe"
if (-not (Test-Path $waysBin)) {
    $waysBin = Join-Path $env:USERPROFILE ".claude\bin\ways"
}
$waysDir = Join-Path $env:USERPROFILE ".claude\hooks\ways"
$cacheDir = Join-Path $env:LOCALAPPDATA "claude-ways\user"

# Nothing to check if this isn't a ways-enabled install
if (-not (Test-Path $waysDir -PathType Container)) { exit 0 }

if (-not (Test-Path $waysBin)) {
    Write-Output @"

Warning: Ways setup incomplete - the ``ways`` binary is not installed.

Hooks will be inactive until setup completes. Run:

    cd ~/.claude && make setup

This downloads the ways binary, embedding model, and generates
the matching corpus. If you don't have a Rust toolchain, pre-built
binaries are downloaded automatically.

"@
    exit 0
}

# Binary exists - check corpus
$corpus = Join-Path $cacheDir "ways-corpus.jsonl"
if (-not (Test-Path $corpus)) {
    Write-Output @"

Warning: Ways corpus not generated - semantic matching is inactive.

Run:

    cd ~/.claude && make setup

"@
    exit 0
}

# Optional: note if embedding model is missing (BM25 still works)
$model = Join-Path $cacheDir "minilm-l6-v2.gguf"
$embedBin = Join-Path $cacheDir "way-embed"
if ((-not (Test-Path $model)) -or (-not (Test-Path $embedBin))) {
    # Only mention this once per day (rate limit via marker file)
    $marker = Join-Path $env:TEMP ".claude-embed-notice-$(Get-Date -Format 'yyyyMMdd')"
    if (-not (Test-Path $marker)) {
        Write-Output @"

Info: Embedding model not installed - using BM25 fallback (91% vs 98% accuracy).

To install the embedding engine:

    cd ~/.claude && make setup

"@
        New-Item $marker -ItemType File -Force | Out-Null
    }
}
