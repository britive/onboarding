#!/usr/bin/env bash
# Commit-message checks for the commits a pull request adds. Usage:
#   .github/scripts/commit-checks.sh <base-ref>
set -euo pipefail
base="${1:?base ref}"

fail=0
while IFS= read -r sha; do
  msg=$(git log -1 --format='%B' "$sha")
  if grep -qiE 'claude|anthropic|co-authored-by' <<<"$msg"; then
    echo "FAIL: commit $sha carries tooling attribution; rewrite the message" >&2
    fail=1
  fi
done < <(git rev-list "$base"..HEAD)

[ "$fail" -eq 0 ] && echo "commit messages ok"
exit "$fail"
