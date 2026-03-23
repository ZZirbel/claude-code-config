#!/bin/bash
# Way frontmatter linter and fixer
#
# Usage:
#   lint-ways.sh                     # lint all ways (global + project)
#   lint-ways.sh <path>              # lint ways under a specific directory
#   lint-ways.sh --fix               # show suggested fixes (does not auto-apply)
#   lint-ways.sh --schema            # print the frontmatter schema
#
# Validates way.md and check.md frontmatter against frontmatter-schema.yaml.
# Flags unknown fields, invalid values, and incomplete conditional pairs.
# Does NOT flag absence of optional fields.

set -uo pipefail

WAYS_DIR="${HOME}/.claude/hooks/ways"
SCHEMA_FILE="${WAYS_DIR}/frontmatter-schema.yaml"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"

MODE="lint"
FIX=false
STRICT=false
TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix)    FIX=true; shift ;;
        --strict) STRICT=true; shift ;;
        --schema) MODE="schema"; shift ;;
        --help|-h)
            sed -n '2,/^$/{ s/^# //; s/^#//; p }' "$0"
            exit 0
            ;;
        *)  TARGET="$1"; shift ;;
    esac
done

# ── Corpus regeneration ──────────────────────────────────────────
# Regenerate ways-corpus.jsonl before linting so IDF is current.
# Only runs if the generator script exists.
CORPUS_GEN="${HOME}/.claude/tools/way-match/generate-corpus.sh"
if [[ -x "$CORPUS_GEN" && "$MODE" == "lint" ]]; then
    bash "$CORPUS_GEN" --quiet "$WAYS_DIR" 2>/dev/null
fi

# ── Schema loading ────────────────────────────────────────────────
# Extract valid field names and enum values from frontmatter-schema.yaml
# Uses awk to avoid dependency on specific yq version

if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo "Error: Schema file not found at $SCHEMA_FILE" >&2
    exit 1
fi

# Extract field names under a top-level type (way or check)
# Reads the schema YAML and collects field names from each category block
extract_fields() {
    local type="$1"  # "way" or "check"
    awk -v type="$type" '
        # Track which top-level block we are in
        /^[a-z]+:$/ { current_type = $0; gsub(/:/, "", current_type); next }
        # Track category blocks (2-space indent)
        current_type == type && /^  [a-z]+:$/ { in_category = 1; next }
        current_type == type && in_category && /^    [a-z_]+:$/ {
            f = $0; gsub(/^    /, "", f); gsub(/:$/, "", f)
            print f
            next
        }
        # Exit category on de-indent
        /^  [a-z]/ && !/^    / { in_category = 0 }
        /^[a-z]/ { in_category = 0; current_type = "" }
    ' "$SCHEMA_FILE"
}

# Extract enum values for a field
extract_enum_values() {
    local type="$1" field="$2"
    awk -v type="$type" -v field="$field" '
        /^[a-z]+:$/ { ct = $0; gsub(/:/, "", ct); next }
        ct == type && $0 ~ "^    " field ":$" { found = 1; next }
        found && /values:/ {
            gsub(/.*\[/, ""); gsub(/\].*/, ""); gsub(/,/, " ")
            print
            found = 0
        }
        found && /^    [a-z]/ { found = 0 }
    ' "$SCHEMA_FILE"
}

# Extract when: subfield names
extract_when_subfields() {
    awk '
        /^        [a-z_]+:$/ && in_when {
            f = $0; gsub(/^        /, "", f); gsub(/:$/, "", f)
            print f
        }
        /^      subfields:/ { in_when = 1; next }
        /^    [a-z]/ && !/^      / { in_when = 0 }
    ' "$SCHEMA_FILE"
}

WAY_FIELDS=$(extract_fields "way" | tr '\n' ' ')
CHECK_FIELDS=$(extract_fields "check" | tr '\n' ' ')
WHEN_SUBFIELDS=$(extract_when_subfields | tr '\n' ' ')
VALID_SCOPES=$(extract_enum_values "way" "scope" | tr -s ' ')
VALID_MACROS=$(extract_enum_values "way" "macro" | tr -s ' ')
VALID_TRIGGERS=$(extract_enum_values "way" "trigger" | tr -s ' ')

# Extract recommended fields from schema
extract_recommended() {
    local type="$1"
    awk -v type="$type" '
        /^[a-z]+:$/ { ct = $0; gsub(/:/, "", ct); next }
        ct == type && /^  [a-z]+:$/ { in_cat = 1; next }
        ct == type && in_cat && /^    [a-z_]+:$/ { fname = $0; gsub(/^    /, "", fname); gsub(/:$/, "", fname); next }
        ct == type && in_cat && /required: recommended/ { print fname }
        /^  [a-z]/ && !/^    / { in_cat = 0 }
        /^[a-z]/ { in_cat = 0; ct = "" }
    ' "$SCHEMA_FILE"
}

WAY_RECOMMENDED=$(extract_recommended "way" | tr '\n' ' ')
CHECK_RECOMMENDED=$(extract_recommended "check" | tr '\n' ' ')

if [[ "$MODE" == "schema" ]]; then
    cat "$SCHEMA_FILE"
    exit 0
fi

# ── Linting logic ─────────────────────────────────────────────────

ERRORS=0
WARNINGS=0

lint_file() {
    local filepath="$1"
    local filetype="$2"  # "way" or "check"
    local relpath="${filepath#$WAYS_DIR/}"
    relpath="${relpath#$PROJECT_DIR/.claude/ways/}"

    # Extract frontmatter
    local frontmatter
    frontmatter=$(awk 'NR==1 && /^---$/{p=1; next} p && /^---$/{exit} p{print}' "$filepath")

    [[ -z "$frontmatter" ]] && {
        echo "  ERROR: $relpath — no YAML frontmatter"
        ((ERRORS++))
        return
    }

    local valid_fields
    if [[ "$filetype" == "check" ]]; then
        valid_fields="$CHECK_FIELDS"
    else
        valid_fields="$WAY_FIELDS"
    fi

    local file_errors=0
    local file_warnings=0

    # Check for multi-line YAML values (> or |) — the trigger pipeline parsers
    # only read single-line values. Multi-line silently returns ">" as the value,
    # breaking semantic matching.
    local multiline_fields
    multiline_fields=$(echo "$frontmatter" | awk '/^[a-z_]+: *[>|] *$/{gsub(/:.*/, ""); print}')
    for mlf in $multiline_fields; do
        echo "  ERROR: $relpath — '$mlf' uses multi-line YAML (> or |) which the trigger pipeline cannot parse. Use a single line."
        ((file_errors++))
        if [[ "$FIX" == "true" ]]; then
            echo "    fix: collapse '$mlf:' value to a single line"
        fi
    done

    # Check for unknown top-level fields
    local fields
    fields=$(echo "$frontmatter" | awk '/^[a-z][a-z_]*:/{print $1}' | sed 's/://')
    for field in $fields; do
        local found=false
        for valid in $valid_fields; do
            [[ "$field" == "$valid" ]] && { found=true; break; }
        done
        if [[ "$found" == "false" ]]; then
            echo "  UNKNOWN: $relpath — unknown field '$field'"
            ((file_warnings++))
            if [[ "$FIX" == "true" ]]; then
                echo "    fix: remove '$field:' line"
            fi
        fi
    done

    # Check description/vocabulary conditional pairing
    local has_desc has_vocab
    has_desc=$(echo "$frontmatter" | grep -c '^description:' || true)
    has_vocab=$(echo "$frontmatter" | grep -c '^vocabulary:' || true)
    if [[ "$has_desc" -gt 0 && "$has_vocab" -eq 0 ]]; then
        echo "  WARNING: $relpath — description without vocabulary (semantic matching incomplete)"
        ((file_warnings++))
    fi
    if [[ "$has_vocab" -gt 0 && "$has_desc" -eq 0 ]]; then
        echo "  WARNING: $relpath — vocabulary without description (semantic matching incomplete)"
        ((file_warnings++))
    fi

    # Check threshold is numeric
    local thresh
    thresh=$(echo "$frontmatter" | awk '/^threshold:/{gsub(/^threshold: */,"");print;exit}')
    if [[ -n "$thresh" ]] && ! echo "$thresh" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        echo "  ERROR: $relpath — threshold '$thresh' is not numeric"
        ((file_errors++))
    fi

    # Check scope enum values
    local scope_val
    scope_val=$(echo "$frontmatter" | awk '/^scope:/{gsub(/^scope: */,"");print;exit}')
    if [[ -n "$scope_val" ]]; then
        IFS=', ' read -ra scope_parts <<< "$scope_val"
        for s in "${scope_parts[@]}"; do
            s=$(echo "$s" | tr -d ' ')
            [[ -z "$s" ]] && continue
            local scope_valid=false
            for vs in $VALID_SCOPES; do
                [[ "$s" == "$vs" ]] && { scope_valid=true; break; }
            done
            if [[ "$scope_valid" == "false" ]]; then
                echo "  ERROR: $relpath — invalid scope '$s' (valid: $VALID_SCOPES)"
                ((file_errors++))
            fi
        done
    fi

    # Check macro enum values
    local macro_val
    macro_val=$(echo "$frontmatter" | awk '/^macro:/{gsub(/^macro: */,"");print;exit}')
    if [[ -n "$macro_val" ]]; then
        local macro_valid=false
        for vm in $VALID_MACROS; do
            [[ "$macro_val" == "$vm" ]] && { macro_valid=true; break; }
        done
        if [[ "$macro_valid" == "false" ]]; then
            echo "  ERROR: $relpath — invalid macro '$macro_val' (valid: $VALID_MACROS)"
            ((file_errors++))
        fi
    fi

    # Check trigger enum values
    local trigger_val
    trigger_val=$(echo "$frontmatter" | awk '/^trigger:/{gsub(/^trigger: */,"");print;exit}')
    if [[ -n "$trigger_val" ]]; then
        local trigger_valid=false
        for vt in $VALID_TRIGGERS; do
            [[ "$trigger_val" == "$vt" ]] && { trigger_valid=true; break; }
        done
        if [[ "$trigger_valid" == "false" ]]; then
            echo "  ERROR: $relpath — invalid trigger '$trigger_val' (valid: $VALID_TRIGGERS)"
            ((file_errors++))
        fi
    fi

    # Check when: sub-fields
    local when_block
    when_block=$(echo "$frontmatter" | awk '/^when:/{found=1;next} found && /^  [a-z]/{print} found && /^[^ ]/{exit}')
    if [[ -n "$when_block" ]]; then
        local when_fields
        when_fields=$(echo "$when_block" | awk '{print $1}' | sed 's/://')
        for wf in $when_fields; do
            local wf_valid=false
            for valid_wf in $WHEN_SUBFIELDS; do
                [[ "$wf" == "$valid_wf" ]] && { wf_valid=true; break; }
            done
            if [[ "$wf_valid" == "false" ]]; then
                echo "  UNKNOWN: $relpath — unknown when: sub-field '$wf'"
                ((file_warnings++))
            fi
        done

        # Verify when.project path exists
        local when_project
        when_project=$(echo "$when_block" | awk '/project:/{gsub(/^  project: */,"");print;exit}')
        if [[ -n "$when_project" ]]; then
            local expanded="${when_project/#\~/$HOME}"
            if [[ ! -d "$expanded" ]]; then
                echo "  WARNING: $relpath — when.project path '$when_project' does not exist"
                ((file_warnings++))
            fi
        fi
    fi

    # Check recommended fields and matching strategy (--strict only)
    if [[ "$STRICT" == "true" ]]; then
        # Flag regex-only ways (have pattern but no semantic matching)
        local has_pattern
        has_pattern=$(echo "$frontmatter" | grep -c '^pattern:' || true)
        if [[ "$has_pattern" -gt 0 && "$has_desc" -eq 0 && "$has_vocab" -eq 0 ]]; then
            echo "  RECOMMEND: $relpath — regex-only matching; add description + vocabulary for natural language coverage"
            ((file_warnings++))
        fi

        # Flag recommended fields (only for semantic ways where they apply)
        local recommended
        if [[ "$filetype" == "check" ]]; then
            recommended="$CHECK_RECOMMENDED"
        else
            recommended="$WAY_RECOMMENDED"
        fi
        for rec in $recommended; do
            # threshold is only recommended for semantic ways
            if [[ "$rec" == "threshold" && "$has_desc" -eq 0 ]]; then
                continue
            fi
            if ! echo "$frontmatter" | grep -q "^${rec}:"; then
                echo "  RECOMMEND: $relpath — missing recommended field '$rec'"
                ((file_warnings++))
                if [[ "$FIX" == "true" ]]; then
                    echo "    fix: add '$rec:' with appropriate value"
                fi
            fi
        done
    fi

    # check.md specific: verify anchor and check sections
    if [[ "$filetype" == "check" ]]; then
        if ! grep -q '^## anchor' "$filepath"; then
            echo "  ERROR: $relpath — check.md missing '## anchor' section"
            ((file_errors++))
        fi
        if ! grep -q '^## check' "$filepath"; then
            echo "  ERROR: $relpath — check.md missing '## check' section"
            ((file_errors++))
        fi
    fi

    ((ERRORS += file_errors))
    ((WARNINGS += file_warnings))
}

# ── Scan ──────────────────────────────────────────────────────────

echo "=== Way Frontmatter Lint ==="
echo "Schema: $SCHEMA_FILE"
echo ""

scan_dir() {
    local dir="$1"
    local label="$2"
    [[ ! -d "$dir" ]] && return

    local count=0
    while IFS= read -r -d '' f; do
        local ftype="way"
        [[ "$f" == *check.md ]] && ftype="check"
        lint_file "$f" "$ftype"
        ((count++))
    done < <(find "$dir" \( -name "way.md" -o -name "check.md" \) -print0 2>/dev/null | sort -z)

    echo ""
    echo "$label: scanned $count files"
}

if [[ -n "$TARGET" ]]; then
    scan_dir "$TARGET" "Target"
else
    if [[ -n "$PROJECT_DIR" && -d "$PROJECT_DIR/.claude/ways" ]]; then
        scan_dir "$PROJECT_DIR/.claude/ways" "Project-local"
    fi
    scan_dir "$WAYS_DIR" "Global"
fi

echo ""
echo "════════════════════════════"
echo "Summary: $ERRORS errors, $WARNINGS warnings"
echo "════════════════════════════"

[[ $ERRORS -gt 0 ]] && exit 1
exit 0
