#!/bin/bash
# Install or update claude-code-config into ~/.claude
# Handles file conflicts like apt: user-edited files get diffed and prompted,
# infrastructure files recommend update with option to skip.
#
# Usage:
#   scripts/install.sh [source_dir]     # install from a local clone
#   scripts/install.sh                  # auto-clone latest and install
#   curl -sL <raw-url> | bash           # self-bootstrap from internet
#
# When run without a source_dir (or via pipe), the script clones the latest
# release to a temp directory, verifies the clone, then re-executes itself
# from the verified copy. This means the curl|bash pattern only bootstraps —
# the actual install logic runs from auditable, git-tracked code.

set -euo pipefail

UPSTREAM_REPO="aaronsb/claude-code-config"
UPSTREAM_URL="https://github.com/${UPSTREAM_REPO}"

# --- Self-bootstrap ---
#
# If no source_dir was provided and we're not already inside a clone,
# fetch the latest version and re-exec from there. This handles:
#   - curl | bash (stdin, no filesystem context)
#   - Running the script directly without cloning first

needs_bootstrap() {
  # Explicit source dir provided — no bootstrap needed
  [[ $# -gt 0 ]] && return 1

  # Check if we're inside a valid repo already
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || return 0
  [[ -f "$script_dir/../hooks/check-config-updates.sh" ]] && return 1

  return 0
}

if needs_bootstrap "$@"; then
  echo ""
  echo "No source directory provided — fetching latest from ${UPSTREAM_REPO}..."
  echo ""

  if ! command -v git &>/dev/null; then
    echo "Error: git is required. Install git and try again."
    exit 1
  fi

  BOOTSTRAP_DIR=$(mktemp -d)
  trap 'rm -rf "$BOOTSTRAP_DIR"' EXIT

  if ! git clone --depth 1 "$UPSTREAM_URL" "$BOOTSTRAP_DIR/claude-code-config" 2>&1; then
    echo "Error: Failed to clone ${UPSTREAM_URL}"
    exit 1
  fi

  CLONE="$BOOTSTRAP_DIR/claude-code-config"

  # Verify the clone is what we expect
  if [[ ! -f "$CLONE/hooks/check-config-updates.sh" ]]; then
    echo "Error: Clone doesn't look like claude-code-config."
    echo "  Expected hooks/check-config-updates.sh — not found."
    exit 1
  fi

  # Verify clean working tree (no unexpected modifications)
  if [[ -n "$(git -C "$CLONE" status --porcelain 2>/dev/null)" ]]; then
    echo "Error: Clone has unexpected modifications. Aborting."
    exit 1
  fi

  # Show what we're about to install
  CLONE_HEAD=$(git -C "$CLONE" log --oneline -1 2>/dev/null)
  echo "Verified clone: ${CLONE_HEAD}"
  echo ""

  # Run from the verified clone, then clean up
  bash "$CLONE/scripts/install.sh" "$CLONE"
  exit $?
fi

# --- Config ---

DEST="${HOME}/.claude"
SRC="${1:-$(cd "$(dirname "$0")/.." && pwd)}"

# Colors (disabled if not a terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

# Counters
COPIED=0
UPDATED=0
SKIPPED=0
CONFLICTS=0
INFRA_SKIPPED=0

# --- Classification ---

# Three tiers of conflict handling:
#   "user"    — config you wrote (CLAUDE.md, settings.json, ways.json)
#               Default: keep. Full merge/diff/replace menu.
#   "content" — ways you may have customized (way.md files)
#               Default: keep. Full merge/diff/replace menu.
#   "infra"   — scripts, docs, plumbing that should match the version
#               Default: update. Option to skip with consistency warning.
classify() {
  local file="$1"
  local basename="${file##*/}"

  # User config — default keep
  case "$basename" in
    CLAUDE.md|settings.json|ways.json) echo "user"; return ;;
  esac

  # Way content files — default keep
  if [[ "$file" == hooks/ways/* && "$basename" == "way.md" ]]; then
    echo "content"; return
  fi

  # Infrastructure — default update
  echo "infra"
}

# --- Conflict UI ---

# Show diff between two files, truncated to 80 lines.
show_diff() {
  local dst_file="$1" src_file="$2"
  echo ""
  echo -e "  ${BOLD}--- local${RESET}"
  echo -e "  ${BOLD}+++ upstream${RESET}"
  diff -u "$dst_file" "$src_file" | tail -n +3 | head -80 | sed 's/^/  /'
  local lines
  lines=$(diff -u "$dst_file" "$src_file" | wc -l)
  if (( lines > 83 )); then
    echo -e "  ${YELLOW}... ($(( lines - 83 )) more lines, run diff manually to see all)${RESET}"
  fi
  echo ""
}

# Prompt for user/content files. Default: keep.
# Returns 0 if file should be replaced, 1 if kept, 2 if merged.
prompt_content_conflict() {
  local relpath="$1"
  local src_file="$2"
  local dst_file="$3"

  echo ""
  echo -e "${YELLOW}CONFLICT:${RESET} ${BOLD}${relpath}${RESET}"
  echo -e "  Local file differs from upstream."
  echo ""

  while true; do
    echo -e "  ${CYAN}[K]${RESET}eep yours  ${CYAN}[R]${RESET}eplace with upstream  ${CYAN}[D]${RESET}iff  ${CYAN}[M]${RESET}erge (if available)"
    read -rp "  Choice [K/r/d/m]: " choice < /dev/tty
    choice="${choice:-k}"

    case "${choice,,}" in
      k)
        echo -e "  ${GREEN}Kept${RESET} local version."
        return 1
        ;;
      r)
        echo -e "  Replaced with upstream version."
        return 0
        ;;
      d)
        show_diff "$dst_file" "$src_file"
        ;;
      m)
        if command -v git &>/dev/null; then
          local merged
          merged=$(mktemp)
          if git merge-file -p "$dst_file" "$dst_file" "$src_file" > "$merged" 2>/dev/null; then
            echo -e "  ${GREEN}Clean merge.${RESET}"
          else
            echo -e "  ${YELLOW}Merge has conflicts${RESET} (marked with <<<<<<<)."
            echo -e "  Review the result — conflict markers need manual resolution."
          fi
          cp "$merged" "$dst_file"
          rm -f "$merged"
          return 2
        else
          echo -e "  ${RED}git not available for merge.${RESET} Choose K or R."
        fi
        ;;
      *)
        echo "  Invalid choice."
        ;;
    esac
  done
}

# Prompt for infrastructure files. Default: update.
# Warns about consistency risks if skipped.
# Returns 0 if file should be replaced, 1 if kept.
prompt_infra_conflict() {
  local relpath="$1"
  local src_file="$2"
  local dst_file="$3"

  echo ""
  echo -e "${CYAN}UPDATE:${RESET} ${BOLD}${relpath}${RESET}"
  echo -e "  Infrastructure file has changed upstream."
  echo ""

  while true; do
    echo -e "  ${CYAN}[U]${RESET}pdate (recommended)  ${CYAN}[S]${RESET}kip  ${CYAN}[D]${RESET}iff"
    read -rp "  Choice [U/s/d]: " choice < /dev/tty
    choice="${choice:-u}"

    case "${choice,,}" in
      u)
        echo -e "  Updated."
        return 0
        ;;
      s)
        echo ""
        echo -e "  ${YELLOW}Warning:${RESET} Skipping infrastructure updates may leave your install in"
        echo -e "  an inconsistent state — ways may reference scripts that have changed."
        echo ""
        echo -e "  If you need to customize infrastructure files, consider:"
        echo -e "    - Maintaining a fork and tracking changes there"
        echo -e "    - Submitting a PR upstream if the change is generally useful"
        echo -e "    - Using project-local ways to override behavior without editing global scripts"
        echo ""
        read -rp "  Skip anyway? [y/N]: " confirm < /dev/tty
        if [[ "${confirm,,}" == "y" ]]; then
          echo -e "  ${YELLOW}Skipped.${RESET}"
          return 1
        fi
        ;;
      d)
        show_diff "$dst_file" "$src_file"
        ;;
      *)
        echo "  Invalid choice."
        ;;
    esac
  done
}

# --- Main ---

echo ""
echo -e "${BOLD}claude-code-config installer${RESET}"
echo -e "Source: ${CYAN}${SRC}${RESET}"
echo -e "Target: ${CYAN}${DEST}${RESET}"
echo ""

# Validate source
if [[ ! -f "$SRC/hooks/check-config-updates.sh" ]]; then
  echo -e "${RED}Error:${RESET} Source doesn't look like claude-code-config."
  echo "  Expected to find hooks/check-config-updates.sh in: $SRC"
  exit 1
fi

# Backup
if [[ -d "$DEST" ]]; then
  BACKUP="${DEST}-backup-$(date +%Y%m%d-%H%M%S)"
  echo -e "Backing up existing config to ${CYAN}${BACKUP}${RESET}"
  cp -a "$DEST" "$BACKUP"
fi

mkdir -p "$DEST"

# Walk all tracked files in source (respects .gitignore)
cd "$SRC"

# Use git ls-files if available (respects gitignore), fall back to find
if git -C "$SRC" rev-parse --git-dir &>/dev/null; then
  file_list=$(git -C "$SRC" ls-files)
else
  file_list=$(find . -type f -not -path './.git/*' | sed 's|^\./||')
fi

while IFS= read -r relpath; do
  # Skip git internals
  [[ "$relpath" == .git/* ]] && continue

  src_file="$SRC/$relpath"
  dst_file="$DEST/$relpath"

  # New file — just copy
  if [[ ! -f "$dst_file" ]]; then
    mkdir -p "$(dirname "$dst_file")"
    cp -a "$src_file" "$dst_file"
    (( COPIED++ ))
    continue
  fi

  # Identical — skip
  if diff -q "$src_file" "$dst_file" &>/dev/null; then
    (( SKIPPED++ ))
    continue
  fi

  # Conflict — classify and handle
  strategy=$(classify "$relpath")

  case "$strategy" in
    user|content)
      (( CONFLICTS++ ))
      if prompt_content_conflict "$relpath" "$src_file" "$dst_file"; then
        cp -a "$src_file" "$dst_file"
      fi
      ;;
    infra)
      if prompt_infra_conflict "$relpath" "$src_file" "$dst_file"; then
        cp -a "$src_file" "$dst_file"
        (( UPDATED++ ))
      else
        (( INFRA_SKIPPED++ ))
      fi
      ;;
  esac

done <<< "$file_list"

# Initialize git tracking if not present
if [[ ! -d "$DEST/.git" ]] && [[ -d "$SRC/.git" ]]; then
  echo ""
  echo -e "Initializing git tracking in ${CYAN}~/.claude${RESET}"
  cp -a "$SRC/.git" "$DEST/.git"
fi

# Make hooks executable
chmod +x "$DEST"/hooks/**/*.sh "$DEST"/hooks/*.sh 2>/dev/null

# Summary
echo ""
echo -e "${BOLD}Done.${RESET}"
echo -e "  ${GREEN}${COPIED}${RESET} new files copied"
echo -e "  ${GREEN}${UPDATED}${RESET} infrastructure files updated"
echo -e "  ${YELLOW}${CONFLICTS}${RESET} content conflicts resolved"
echo -e "  ${CYAN}${SKIPPED}${RESET} unchanged (skipped)"
if (( INFRA_SKIPPED > 0 )); then
  echo -e "  ${RED}${INFRA_SKIPPED}${RESET} infrastructure updates skipped (review recommended)"
fi
if [[ -n "${BACKUP:-}" ]]; then
  echo -e "  Backup at: ${CYAN}${BACKUP}${RESET}"
fi
echo ""
echo -e "Restart Claude Code for changes to take effect."
echo -e "Review hooks at: ${CYAN}~/.claude/hooks/${RESET}"
echo ""
