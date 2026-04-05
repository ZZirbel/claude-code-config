---
description: Run governance traceability report — provenance coverage, control queries, way traces
---

Run `ways governance` with the user's arguments (if any) and display the output.

This is the governance operator. Common invocations:

- `ways governance report` — coverage report (default)
- `ways governance trace softwaredev/commits` — end-to-end trace for a way
- `ways governance control NIST` — which ways implement controls matching "NIST"
- `ways governance policy code-lifecycle` — which ways derive from a policy
- `ways governance gaps` — list ways without provenance
- `ways governance stale` — ways with stale verified dates
- `ways governance active` — cross-reference provenance with way firing stats
- `ways governance matrix` — flat traceability matrix (way | control | justification)
- `ways governance lint` — validate provenance integrity
- Add `--json` to any mode for machine-readable output

If the user provides arguments after `/governance`, pass them through. If no arguments, run the default coverage report.
