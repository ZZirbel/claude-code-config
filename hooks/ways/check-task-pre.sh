#!/bin/bash
# PreToolUse:Task - Stash subagent-scoped ways for SubagentStart
#
# TRIGGER FLOW:
# ┌─────────────────┐     ┌──────────────────┐     ┌───────────────┐
# │ PreToolUse:Task │────▶│ scan_ways()      │────▶│ write stash   │
# │ (hook event)    │     │ scope: subagent  │     │ for injection │
# └─────────────────┘     └──────────────────┘     └───────────────┘
#
# Phase 1 of two-phase subagent injection:
# 1. PreToolUse:Task scans Task prompt against ways with subagent scope
# 2. SubagentStart (inject-subagent.sh) reads stash and emits content
#
# Stash: /tmp/.claude-subagent-stash-{session_id}/{timestamp}.json

INPUT=$(cat)
TASK_PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' | tr '[:upper:]' '[:lower:]')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(echo "$INPUT" | jq -r '.cwd // empty')}"
WAYS_DIR="${HOME}/.claude/hooks/ways"

# Detect teammate spawn (Task tool with team_name parameter)
TEAM_NAME=$(echo "$INPUT" | jq -r '.tool_input.team_name // empty')
IS_TEAMMATE=false
[[ -n "$TEAM_NAME" ]] && IS_TEAMMATE=true

[[ -z "$TASK_PROMPT" ]] && exit 0
[[ -z "$SESSION_ID" ]] && exit 0

STASH_DIR="/tmp/.claude-subagent-stash-${SESSION_ID}"
mkdir -p "$STASH_DIR"

MATCHED_WAYS=()

scan_ways_for_subagent() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return

  while IFS= read -r -d '' wayfile; do
    waypath="${wayfile#$dir/}"
    waypath="${waypath%/way.md}"

    # Extract frontmatter
    frontmatter=$(awk 'NR==1 && /^---$/{p=1; next} p && /^---$/{exit} p{print}' "$wayfile")
    get_field() { echo "$frontmatter" | awk "/^$1:/"'{gsub(/^'"$1"': */, ""); print; exit}'; }

    # Must have subagent or teammate scope
    local scope_raw=$(get_field "scope")
    scope_raw="${scope_raw:-agent}"
    if $IS_TEAMMATE; then
      # Teammates match ways with scope: teammate OR subagent
      echo "$scope_raw" | grep -qwE "subagent|teammate" || continue
    else
      echo "$scope_raw" | grep -qw "subagent" || continue
    fi

    # Skip state-triggered ways (they don't match on content)
    local trigger=$(get_field "trigger")
    [[ -n "$trigger" ]] && continue

    # Match against task prompt (same logic as check-prompt.sh)
    local match_mode=$(get_field "match")
    local pattern=$(get_field "pattern")
    local description=$(get_field "description")
    local vocabulary=$(get_field "vocabulary")
    local threshold=$(get_field "threshold")

    local matched=false

    if [[ "$match_mode" == "model" && -n "$description" ]]; then
      if "${WAYS_DIR}/model-match.sh" "$TASK_PROMPT" "$description" 2>/dev/null; then
        matched=true
      fi
    elif [[ "$match_mode" == "semantic" && -n "$description" && -n "$vocabulary" ]]; then
      if "${WAYS_DIR}/semantic-match.sh" "$TASK_PROMPT" "$description" "$vocabulary" "$threshold" 2>/dev/null; then
        matched=true
      fi
    elif [[ -n "$pattern" && "$TASK_PROMPT" =~ $pattern ]]; then
      matched=true
    fi

    if $matched; then
      MATCHED_WAYS+=("$waypath")
    fi
  done < <(find "$dir" -name "way.md" -print0 2>/dev/null)
}

# Scan project-local first, then global
scan_ways_for_subagent "$PROJECT_DIR/.claude/ways"
scan_ways_for_subagent "${WAYS_DIR}"

# Write stash if any ways matched
if [[ ${#MATCHED_WAYS[@]} -gt 0 ]]; then
  TIMESTAMP=$(date +%s%N)
  STASH_FILE="${STASH_DIR}/${TIMESTAMP}.json"

  WAYS_JSON=$(printf '%s\n' "${MATCHED_WAYS[@]}" | jq -R . | jq -s .)
  jq -n --argjson ways "$WAYS_JSON" --argjson teammate "$IS_TEAMMATE" \
    '{ways: $ways, is_teammate: $teammate}' > "$STASH_FILE"
fi

# Never block Task creation
exit 0
