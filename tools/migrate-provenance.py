#!/usr/bin/env python3
"""Migrate provenance: blocks from way.md frontmatter to provenance.yaml sidecars.

Usage:
    python3 migrate-provenance.py [--dry-run] [--ways-dir DIR]

Finds all way*.md files with provenance: in frontmatter, extracts the block
to provenance.yaml in the same directory, and removes it from the way file.
"""

import argparse
import os
import re
import sys
from pathlib import Path


def find_way_files_with_provenance(ways_dir):
    """Find all way*.md files that have a provenance: block in frontmatter."""
    results = []
    for root, _, files in os.walk(ways_dir):
        for f in files:
            if f.startswith("way") and f.endswith(".md"):
                path = Path(root) / f
                text = path.read_text()
                if has_provenance_in_frontmatter(text):
                    results.append(path)
    return sorted(results)


def has_provenance_in_frontmatter(text):
    """Check if text has a provenance: key inside YAML frontmatter."""
    lines = text.splitlines()
    if not lines or lines[0].strip() != '---':
        return False
    for line in lines[1:]:
        if line.strip() == '---':
            break
        if line.startswith('provenance:'):
            return True
    return False


def extract_provenance(text):
    """Extract provenance block from frontmatter, return (provenance_yaml, cleaned_text).

    The provenance_yaml is the content suitable for provenance.yaml (without the
    top-level 'provenance:' key — the nested content becomes top-level).
    The cleaned_text is the original file with the provenance block removed.
    """
    lines = text.splitlines(keepends=True)

    # Find frontmatter boundaries
    if not lines or lines[0].strip() != '---':
        return None, text

    fm_end = None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == '---':
            fm_end = i
            break

    if fm_end is None:
        return None, text

    # Find provenance block within frontmatter
    prov_start = None
    prov_end = None

    for i in range(1, fm_end):
        line = lines[i]
        if line.startswith('provenance:'):
            prov_start = i
            # Find where provenance block ends — next line at indent 0 or frontmatter end
            for j in range(i + 1, fm_end):
                stripped = lines[j].rstrip('\n\r')
                if stripped == '' or stripped[0] != ' ':
                    prov_end = j
                    break
            if prov_end is None:
                prov_end = fm_end
            break

    if prov_start is None:
        return None, text

    # Extract provenance lines
    prov_lines = lines[prov_start + 1:prov_end]

    # De-indent by 2 spaces (provenance content is indented under provenance:)
    dedented = []
    for line in prov_lines:
        raw = line.rstrip('\n\r')
        if raw.startswith('  '):
            dedented.append(raw[2:] + '\n')
        elif raw.strip() == '':
            dedented.append('\n')
        else:
            dedented.append(raw + '\n')

    provenance_yaml = ''.join(dedented).rstrip('\n') + '\n'

    # Remove provenance block from original, collapsing blank lines
    cleaned_lines = lines[:prov_start] + lines[prov_end:]

    # Remove trailing blank lines before frontmatter close
    # Find the new frontmatter close position
    new_fm_end = None
    for i, line in enumerate(cleaned_lines[1:], start=1):
        if line.strip() == '---':
            new_fm_end = i
            break

    if new_fm_end is not None:
        # Strip blank lines immediately before the closing ---
        while new_fm_end > 1 and cleaned_lines[new_fm_end - 1].strip() == '':
            cleaned_lines.pop(new_fm_end - 1)
            new_fm_end -= 1

    cleaned_text = ''.join(cleaned_lines)
    return provenance_yaml, cleaned_text


def main():
    parser = argparse.ArgumentParser(description='Migrate provenance blocks to sidecar files')
    parser.add_argument('--dry-run', action='store_true', help='Show what would be done')
    parser.add_argument('--ways-dir', default=os.path.expanduser('~/.claude/hooks/ways'),
                        help='Ways directory (default: ~/.claude/hooks/ways)')
    args = parser.parse_args()

    ways_dir = Path(args.ways_dir)
    files = find_way_files_with_provenance(ways_dir)

    print(f"Found {len(files)} way files with provenance blocks\n")

    for path in files:
        rel = path.relative_to(ways_dir)
        sidecar = path.parent / 'provenance.yaml'
        text = path.read_text()
        prov_yaml, cleaned = extract_provenance(text)

        if prov_yaml is None:
            print(f"  SKIP {rel} — could not extract provenance")
            continue

        if args.dry_run:
            print(f"  {rel}")
            print(f"    → {sidecar.relative_to(ways_dir)}")
            print(f"    provenance: {len(prov_yaml.splitlines())} lines")
            print(f"    way.md: {len(text.splitlines())} → {len(cleaned.splitlines())} lines")
            print()
        else:
            sidecar.write_text(prov_yaml)
            path.write_text(cleaned)
            print(f"  {rel} → {sidecar.name} ({len(prov_yaml.splitlines())} lines extracted)")

    if args.dry_run:
        print("Dry run — no files modified.")
    else:
        print(f"\nDone. {len(files)} provenance.yaml files created.")
        print("Validate with: governance/governance.sh --matrix")


if __name__ == '__main__':
    main()
