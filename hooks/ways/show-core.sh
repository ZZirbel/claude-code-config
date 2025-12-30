#!/bin/bash
# Show core.md with dynamic table from macro
# Runs macro.sh first, then outputs static content from core.md

WAYS_DIR="${HOME}/.claude/hooks/ways"

# Run macro to generate dynamic table
"${WAYS_DIR}/macro.sh"

# Output static content (skip frontmatter)
awk 'BEGIN{fm=0} /^---$/{fm++; next} fm!=1' "${WAYS_DIR}/core.md"
