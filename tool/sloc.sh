#!/usr/bin/env bash
# Count lines of code per top-level folder for git-tracked files.
# Respects .gitignore (only counts what `git ls-files` reports), so build
# artifacts, .dart_tool, .venv, etc. are excluded automatically.
#
# Usage:
#   tool/sloc.sh           # all tracked files, grouped by top-level path
#   tool/sloc.sh --dart    # only .dart source files (excludes _archive)
#   tool/sloc.sh --app     # shipping app code: lib + macos + android + linux
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

filter="${1:-}"

list_files() {
  case "$filter" in
    --dart)
      git ls-files -z -- '*.dart' ':!:_archive/**'
      ;;
    --app)
      git ls-files -z -- 'lib/**' 'macos/**' 'android/**' 'linux/**'
      ;;
    *)
      git ls-files -z
      ;;
  esac
}

list_files | while IFS= read -r -d '' f; do
  top="${f%%/*}"
  [ "$top" = "$f" ] && top="(root files)"
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  printf '%s\t%s\n' "$top" "$lines"
done | awk -F'\t' '
  { lines[$1]+=$2; files[$1]++; tl+=$2; tf++ }
  END {
    printf "%-18s %10s %8s\n", "FOLDER", "LINES", "FILES"
    printf "%-18s %10s %8s\n", "------", "-----", "-----"
    n=0
    for (k in lines) { keys[n]=k; n++ }
    # simple sort by lines desc
    for (i=0;i<n;i++) for (j=i+1;j<n;j++)
      if (lines[keys[j]]>lines[keys[i]]) { t=keys[i]; keys[i]=keys[j]; keys[j]=t }
    for (i=0;i<n;i++) printf "%-18s %10d %8d\n", keys[i], lines[keys[i]], files[keys[i]]
    printf "%-18s %10s %8s\n", "------", "-----", "-----"
    printf "%-18s %10d %8d\n", "TOTAL", tl, tf
  }'
