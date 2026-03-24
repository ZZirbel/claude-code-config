#!/bin/bash
# PreToolUse: Check bash commands against way frontmatter
#
# TRIGGER FLOW:
# ┌─────────────────┐     ┌─────────────────┐     ┌──────────────┐
# │ PreToolUse:Bash │────▶│ scan_ways()     │────▶│ show-way.sh  │
# │ (hook event)    │     │ for each way.md │     │ (idempotent) │
# └─────────────────┘     │  if commands OR │     └──────────────┘
#                         │  keywords match │
#                         └─────────────────┘
#
# Ways are nested: domain/wayname/way.md (e.g., softwaredev/delivery/github/way.md)
# Multiple ways can match a single command - CONTEXT accumulates
# all matching way outputs. Markers prevent duplicate content.
# Output is returned as additionalContext JSON for Claude to see.

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
DESC=$(echo "$INPUT" | jq -r '.tool_input.description // empty' | tr '[:upper:]' '[:lower:]')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(echo "$INPUT" | jq -r '.cwd // empty')}"

CONTEXT=""

# Detect execution scope (agent vs teammate)
source "${HOME}/.claude/hooks/ways/detect-scope.sh"
CURRENT_SCOPE=$(detect_scope "$SESSION_ID")

# Epoch counter
source "${HOME}/.claude/hooks/ways/epoch.sh"
bump_epoch "$SESSION_ID"

# Shared matching logic (provides check_when_preconditions)
source "${HOME}/.claude/hooks/ways/match-way.sh"

# Scan ways in a directory (recursive)
scan_ways() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return

  # Find all way.md files recursively
  while IFS= read -r -d '' wayfile; do
    # Extract way path relative to ways dir (e.g., "softwaredev/delivery/github")
    waypath="${wayfile#$dir/}"
    waypath="${waypath%/way.md}"

    # Extract frontmatter
    frontmatter=$(awk 'NR==1 && /^---$/{p=1; next} p && /^---$/{exit} p{print}' "$wayfile")

    # Extract frontmatter fields
    commands=$(echo "$frontmatter" | awk '/^commands:/{gsub(/^commands: */,"");print;exit}')
    pattern=$(echo "$frontmatter" | awk '/^pattern:/{gsub(/^pattern: */,"");print;exit}')

    # Check scope -- skip if current scope not in way's scope list
    scope=$(echo "$frontmatter" | awk '/^scope:/{gsub(/^scope: */,"");print;exit}')
    scope="${scope:-agent}"
    scope_matches "$scope" "$CURRENT_SCOPE" || continue

    # Check when: preconditions -- deterministic gate before matching
    check_when_preconditions "$frontmatter" || continue

    # Check command patterns
    if [[ -n "$commands" && "$CMD" =~ $commands ]]; then
      CONTEXT+=$(~/.claude/hooks/ways/show-way.sh "$waypath" "$SESSION_ID" "bash")
    fi

    # Check description against pattern (for tool description matching)
    if [[ -n "$DESC" && -n "$pattern" && "$DESC" =~ $pattern ]]; then
      CONTEXT+=$(~/.claude/hooks/ways/show-way.sh "$waypath" "$SESSION_ID" "bash")
    fi
  done < <(find -L "$dir" -name "way.md" -print0 2>/dev/null)
}

# Scan project-local first, then global
scan_ways "$PROJECT_DIR/.claude/ways"
scan_ways "${HOME}/.claude/hooks/ways"

# --- Check scanning ---
# match-way.sh already sourced above; just init the semantic engine
detect_semantic_engine

scan_checks() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return

  while IFS= read -r -d '' checkfile; do
    waypath="${checkfile#$dir/}"
    waypath="${waypath%/check.md}"

    frontmatter=$(awk 'NR==1 && /^---$/{p=1; next} p && /^---$/{exit} p{print}' "$checkfile")
    get_field() { echo "$frontmatter" | awk "/^$1:/"'{gsub(/^'"$1"': */, ""); print; exit}'; }

    description=$(get_field "description")
    vocabulary=$(get_field "vocabulary")
    threshold=$(get_field "threshold")
    scope=$(get_field "scope")
    scope="${scope:-agent}"
    scope_matches "$scope" "$CURRENT_SCOPE" || continue

    # Match against command + description
    local query="$CMD $DESC"
    MATCH_SCORE="0"

    local commands_pattern=$(get_field "commands")
    if [[ -n "$commands_pattern" && "$CMD" =~ $commands_pattern ]]; then
      MATCH_SCORE="3.0"
    elif [[ -n "$description" && -n "$vocabulary" ]]; then
      case "$SEMANTIC_ENGINE" in
        bm25)
          local pair_out
          pair_out=$("$WAY_MATCH_BIN" pair \
            --description "$description" \
            --vocabulary "$vocabulary" \
            --query "$query" \
            --threshold "0.0" 2>&1 || true)
          MATCH_SCORE=$(echo "$pair_out" | sed -n 's/.*score=\([0-9.]*\).*/\1/p')
          MATCH_SCORE="${MATCH_SCORE:-0}"
          ;;
        ncd)
          if "${HOME}/.claude/hooks/ways/semantic-match.sh" "$query" "$description" "$vocabulary" "0.58" 2>/dev/null; then
            MATCH_SCORE="2.5"
          fi
          ;;
      esac
    fi

    if [[ "$MATCH_SCORE" != "0" ]]; then
      local check_out
      check_out=$("${HOME}/.claude/hooks/ways/show-check.sh" "$waypath" "$SESSION_ID" "bash" "$MATCH_SCORE")
      [[ -n "$check_out" ]] && CONTEXT+="$check_out"
    fi
  done < <(find -L "$dir" -name "check.md" -print0 2>/dev/null)
}

scan_checks "$PROJECT_DIR/.claude/ways"
scan_checks "${HOME}/.claude/hooks/ways"

# Output JSON - PreToolUse format with decision + additionalContext
if [[ -n "$CONTEXT" ]]; then
  jq -n --arg ctx "$CONTEXT" '{
    "decision": "approve",
    "additionalContext": $ctx
  }'
fi
