---
description: supply chain dependency security audit
vocabulary: dependency supply chain package audit vulnerability npm pip cargo crate
threshold: 1.5
commands: ^(npm|pip|cargo)\ (install|add)
scope: agent
---
# Supply Chain

Audit dependencies before adding them.
