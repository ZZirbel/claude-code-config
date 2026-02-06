# Governance Traceability

Tools for tracing the chain from regulatory frameworks through policy documents to compiled agent guidance (ways).

```
Regulatory Framework → Control → Policy Document → Way → Agent Context
```

## What's Here

| File | Purpose |
|------|---------|
| `provenance-scan.py` | Scan way.md files, extract provenance metadata, generate manifest |
| `provenance-verify.sh` | Coverage report — which ways have provenance, which controls are addressed |

## Quick Start

```bash
# Generate a coverage report
bash governance/provenance-verify.sh

# Generate the manifest as JSON
python3 governance/provenance-scan.py -o provenance-manifest.json

# Cross-reference with an external audit ledger
bash governance/provenance-verify.sh --ledger /path/to/audit-ledger.json

# Machine-readable output
bash governance/provenance-verify.sh --json
```

## How It Works

Ways can include a `provenance:` block in their YAML frontmatter:

```yaml
provenance:
  policy:
    - uri: docs/hooks-and-ways/softwaredev/code-lifecycle.md
      type: governance-doc
  controls:
    - NIST SP 800-53 CM-3 (Configuration Change Control)
  verified: 2026-02-05
  rationale: >
    Conventional commits create structured change records,
    implementing auditable configuration change control.
```

The runtime strips all frontmatter before injecting guidance — provenance is metadata only, zero tokens in the agent's context window.

The scanner reads these blocks and generates a manifest with inverted indices (policy → ways, control → ways). The verifier reads the manifest and reports coverage.

## Making This Its Own Repo

This directory is designed to be separable. To use it as a standalone governance toolkit:

1. Copy the `governance/` directory to a new repo
2. Point `WAYS_DIR` in the scripts to wherever your ways live
3. Add `provenance:` blocks to your ways referencing your own policy documents
4. Optionally connect to an audit ledger for cross-repo control verification

The tools have no dependencies beyond Python 3 and bash + jq.

See [ADR-005](../docs/adr/ADR-005-governance-traceability.md) for the design rationale and [provenance.md](../docs/hooks-and-ways/provenance.md) for the full documentation.
