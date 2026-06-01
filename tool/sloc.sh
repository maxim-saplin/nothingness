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

# SLOC = lines of *source code*. Skip binary assets (running `wc -l` over a PNG
# is meaningless) and machine-generated / tool-managed files (Xcode project
# metadata, plugin registrants, lockfiles) — the way cloc/scc/tokei do. All
# platforms and files remain in the repo; this only fixes what counts as a
# "line of code".
is_source() {
  case "$1" in
    *.png|*.webp|*.jpg|*.jpeg|*.gif|*.ico|*.icns|*.bmp|*.svg|*.ttf|*.otf|*.woff|*.woff2|*.wav|*.mp3|*.flac|*.ogg|*.opus|*.m4a|*.bin) return 1 ;;
    *.lock|*.pbxproj|*.xcscheme|*.xcworkspacedata|*.xib|*.storyboard) return 1 ;;
    *[Gg]eneratedPluginRegistrant.*|*generated_plugin_registrant.*|*/Generated.xcconfig|*/flutter_export_environment.sh|*.g.dart|*.freezed.dart) return 1 ;;
  esac
  return 0
}

list_files | while IFS= read -r -d '' f; do
  is_source "$f" || continue
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
