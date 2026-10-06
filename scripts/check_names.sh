#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
list="scripts/names.local.txt"

if [[ ! -s "$list" ]]; then
  echo "check_names: $list is missing or empty. Add one forbidden name per line." >&2
  exit 2
fi

patterns="$(mktemp)"
trap 'rm -f "$patterns"' EXIT
grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$list" > "$patterns"

found=0

echo "== Working tree (tracked files) =="
if git grep -n -I -i -w -F -f "$patterns" -- . ':!scripts/names.local.txt'; then
  found=1
fi

echo "== Git history (diffs, messages, authors) =="
if git log --all -p --format='commit %H%nAuthor: %an <%ae>%n%B' | grep -n -i -w -F -f "$patterns"; then
  found=1
fi

if [[ "$found" -eq 1 ]]; then
  echo "check_names: forbidden names found." >&2
  exit 1
fi
echo "check_names: clean ($(wc -l < "$patterns" | tr -d ' ') names checked)."
