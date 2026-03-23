#!/bin/bash
# Shared library for ways tooling — sourced by generate-corpus.sh,
# check-embedding-staleness.sh, embed-status.sh, and lint-ways.sh.
#
# Provides:
#   content_hash         — content-addressed hash of way files
#   resolve_project_path — decode Claude Code's lossy path encoding
#   json_escape          — safe string embedding in JSON
#   enumerate_projects   — iterate all projects with .claude/ways/

# Content-addressed hash of all way.md files in a directory.
# Immune to clock skew, catches uncommitted edits.
content_hash() {
  local dir="$1"
  if command -v sha256sum &>/dev/null; then
    find "$dir" -name "way.md" -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum | cut -d' ' -f1
  elif command -v shasum &>/dev/null; then
    find "$dir" -name "way.md" -type f -exec shasum -a 256 {} + 2>/dev/null | sort | shasum -a 256 | cut -d' ' -f1
  else
    echo "no-hash-tool"
  fi
}

# Resolve real project path from Claude Code's encoded directory name.
# Claude Code's path encoding (/ → -) is lossy — paths with hyphens
# can't be decoded. We read sessions-index.json for the real path.
resolve_project_path() {
  local encoded_dir="$1"
  local projects_dir="${HOME}/.claude/projects"
  local idx="${projects_dir}/${encoded_dir}/sessions-index.json"
  if [[ -f "$idx" ]] && command -v jq &>/dev/null; then
    jq -r '.entries[0].projectPath // empty' "$idx" 2>/dev/null
  fi
}

# Escape a string for safe JSON embedding (handles quotes and backslashes)
json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Greedily resolve an encoded path against the filesystem.
# Splits on -, accumulates segments into path components, testing
# the filesystem at each step to distinguish / from - in the original.
# e.g., -home-aaron-Projects-app-github-manager resolves to
# /home/aaron/Projects/app/github-manager
_resolve_encoded_path() {
  local encoded="$1"
  # Split into segments on -
  local IFS='-'
  local segments=()
  read -ra segments <<< "${encoded#-}"

  local current=""
  local pending=""

  for seg in "${segments[@]}"; do
    if [[ -z "$pending" ]]; then
      # Try as new path component: current/seg
      if [[ -d "${current}/${seg}" ]]; then
        current="${current}/${seg}"
      else
        # Start accumulating a hyphenated name
        pending="$seg"
      fi
    else
      # We're accumulating — try both:
      # 1. pending-seg as a single hyphenated component
      # 2. pending as component, seg as new component
      if [[ -d "${current}/${pending}-${seg}" ]]; then
        current="${current}/${pending}-${seg}"
        pending=""
      elif [[ -d "${current}/${pending}/${seg}" ]]; then
        current="${current}/${pending}/${seg}"
        pending=""
      else
        # Keep accumulating
        pending="${pending}-${seg}"
      fi
    fi
  done

  # Handle remaining pending segment
  if [[ -n "$pending" ]]; then
    if [[ -d "${current}/${pending}" ]]; then
      current="${current}/${pending}"
    else
      return  # couldn't resolve
    fi
  fi

  [[ -d "$current" ]] && echo "$current"
}

# Enumerate all Claude Code projects that have .claude/ways/.
# Outputs one line per project: encoded_name|real_path|way_count|semantic_count
#
# Usage:
#   enumerate_projects | while IFS='|' read -r encoded path way_count sem_count; do
#     ...
#   done
enumerate_projects() {
  local projects_dir="${HOME}/.claude/projects"
  [[ -d "$projects_dir" ]] || return

  # Dedup: multiple encoded dirs may resolve to the same repo root
  # (e.g., project invoked from a subdirectory walks up to the same .claude/ways/)
  local _seen_paths=""

  while IFS= read -r projdir; do
    local encoded
    encoded=$(basename "$projdir")
    local project_path
    project_path=$(resolve_project_path "$encoded")

    # Fallback: if no sessions-index.json, greedily resolve against filesystem.
    # Splits encoded path on -, tries each segment as a directory separator
    # or part of a hyphenated name. Handles github-manager, platform-ops, etc.
    if [[ -z "$project_path" ]]; then
      project_path=$(_resolve_encoded_path "$encoded")
    fi
    [[ -z "$project_path" ]] && continue

    # Find .claude/ways/ — may be at projectPath or a parent directory.
    # Claude Code's projectPath points to where it was invoked, which may
    # be a subdirectory of the repo root where .claude/ways/ lives.
    local ways_dir=""
    local check="$project_path"
    while [[ "$check" != "/" && "$check" != "$HOME" ]]; do
      if [[ -d "${check}/.claude/ways" ]]; then
        ways_dir="${check}/.claude/ways"
        project_path="$check"  # update to the repo root
        break
      fi
      check=$(dirname "$check")
    done
    [[ -z "$ways_dir" ]] && continue

    # Dedup: skip if we already emitted this project path
    if echo "$_seen_paths" | grep -qF "$project_path"; then
      continue
    fi
    _seen_paths="${_seen_paths}${project_path}
"

    local way_count
    way_count=$(find "$ways_dir" -name "way.md" -type f 2>/dev/null | wc -l | tr -d ' ')
    [[ $way_count -eq 0 ]] && continue

    # Count semantic ways (have both description and vocabulary)
    local sem_count=0
    while IFS= read -r wf; do
      local fm
      fm=$(awk 'NR==1 && /^---$/{p=1;next} p && /^---$/{exit} p{print}' "$wf")
      if echo "$fm" | grep -q '^description:' && echo "$fm" | grep -q '^vocabulary:'; then
        sem_count=$((sem_count + 1))
      fi
    done < <(find "$ways_dir" -name "way.md" -type f 2>/dev/null)

    echo "${encoded}|${project_path}|${way_count}|${sem_count}"
  done < <(find "$projects_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
}
