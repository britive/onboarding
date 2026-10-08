#!/usr/bin/env bash
# Whole-repository checks. Run locally from the repository root before
# opening a pull request; CI runs the same script.
#
# Requires: git, python3, shellcheck, cfn-lint.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

echo "== tracked files that are empty"
while IFS= read -r -d '' f; do
  [ -s "$f" ] || [ "$(basename "$f")" = ".gitkeep" ] || err "empty file: $f"
done < <(git ls-files -z)

echo "== tracked files hidden by .gitignore"
hidden=$(git ls-files -ci --exclude-standard)
[ -z "$hidden" ] || err "tracked but ignored (customers' clones will differ):"$'\n'"$hidden"

echo "== relative markdown links"
python3 - <<'PY' || fail=1
import os, re, sys, urllib.parse
bad = 0
for root, dirs, fs in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.git', '.venv', 'node_modules')]
    for f in (x for x in fs if x.endswith('.md')):
        p = os.path.join(root, f)
        for m in re.finditer(r'\[[^\]]*\]\(([^)]+)\)', open(p, encoding='utf-8').read()):
            link = m.group(1).split()[0]
            if link.startswith(('http://', 'https://', '#', 'mailto:')):
                continue
            target = urllib.parse.unquote(link.split('#')[0])
            if target and not os.path.exists(os.path.normpath(os.path.join(root, target))):
                print(f'FAIL: broken link {p} -> {link}', file=sys.stderr); bad += 1
sys.exit(1 if bad else 0)
PY

echo "== identifiers that must not be published"
# Real tenant subdomains, account IDs, keys, internal addresses. Placeholders
# are allowed; anything else is a leak until proven otherwise.
pattern='(AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[0-9]{12}\.dkr\.ecr|arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:|[a-z0-9.-]+\.britive-app\.com|[A-Za-z0-9._%+-]+@britive\.com|hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+|xox[baprs]-[0-9A-Za-z-]+)'
allow='(123456789012|111111111111|000000000000|<[^>]*>\.britive-app\.com|(your-tenant|acme|acme\.us-east|mycompany|example|tenant|subdomain|demo)\.britive-app\.com|<[^>]*>\.dkr\.ecr|arn:aws:[a-z0-9-]+:[a-z0-9-]*:(123456789012|111111111111|000000000000):)'
hits=$(git grep -nIE "$pattern" -- . ':!AUDIT.md' | grep -vE "$allow" || true)
[ -z "$hits" ] || err "possible published identifiers (add a placeholder or extend the allow list in this script):"$'\n'"$hits"

echo "== tooling attribution"
hits=$(git grep -nIiE 'claude|anthropic|co-authored-by' -- . ':!.github/scripts/repo-checks.sh' ':!.github/scripts/commit-checks.sh' || true)
[ -z "$hits" ] || err "tooling attribution is not published in this repository:"$'\n'"$hits"

echo "== shell scripts"
while IFS= read -r -d '' f; do
  bash -n "$f" || err "syntax: $f"
done < <(git ls-files -z '*.sh')
git ls-files -z '*.sh' | xargs -0 -r shellcheck -S warning || err "shellcheck"

echo "== CloudFormation templates (every YAML that declares AWSTemplateFormatVersion)"
mapfile -d '' templates < <(git ls-files -z '*.yaml' '*.yml' | xargs -0 grep -l --null '^AWSTemplateFormatVersion')
if [ "${#templates[@]}" -gt 0 ]; then
  cfn-lint --non-zero-exit-code error "${templates[@]}" || err "cfn-lint"
fi

echo "== python compiles"
git ls-files -z '*.py' | xargs -0 -r -n1 python3 -m py_compile || err "py_compile"

if [ "$fail" -ne 0 ]; then
  echo "repository checks failed" >&2
  exit 1
fi
echo "repository checks passed"
