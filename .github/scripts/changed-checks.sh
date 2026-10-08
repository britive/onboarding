#!/usr/bin/env bash
# Checks for the files a change touches. Usage:
#   .github/scripts/changed-checks.sh <base-ref>     (e.g. origin/main)
#
# Requires: git, ruff, yamllint, terraform, tflint, helm.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
base="${1:?base ref, e.g. origin/main}"

mapfile -t files < <(git diff --name-only --diff-filter=ACMR "$base"...HEAD)
if [ "${#files[@]}" -eq 0 ]; then
  echo "no changed files"; exit 0
fi

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }
in_list() { local n="$1"; shift; printf '%s\n' "$@" | grep -qxF -- "$n"; }

py=(); yaml=(); tfdirs=(); charts=()
for f in "${files[@]}"; do
  case "$f" in
    *.py) py+=("$f") ;;
    *.tf|*.tfvars.example) d=$(dirname "$f"); in_list "$d" "${tfdirs[@]:-}" || tfdirs+=("$d") ;;
  esac
  case "$f" in
    */charts/*/*) c=$(sed -E 's#^(.*/charts/[^/]+)/.*#\1#' <<<"$f"); in_list "$c" "${charts[@]:-}" || charts+=("$c") ;;
    *.yaml|*.yml)
      # CloudFormation is covered by cfn-lint in repo-checks; Helm templates are not plain YAML.
      grep -q '^AWSTemplateFormatVersion' "$f" || yaml+=("$f") ;;
  esac
done

if [ "${#py[@]}" -gt 0 ]; then
  echo "== ruff: ${py[*]}"
  ruff check "${py[@]}" || err "ruff"
fi

if [ "${#yaml[@]}" -gt 0 ]; then
  echo "== yamllint: ${yaml[*]}"
  yamllint -c .yamllint "${yaml[@]}" || err "yamllint"
fi

for d in "${tfdirs[@]:-}"; do
  [ -n "$d" ] || continue
  echo "== terraform: $d"
  terraform -chdir="$d" fmt -check -diff || err "terraform fmt $d"
  terraform -chdir="$d" init -backend=false -input=false >/dev/null || err "terraform init $d"
  terraform -chdir="$d" validate || err "terraform validate $d"
  tflint --chdir="$d" || err "tflint $d"
  rm -rf "$d/.terraform" "$d/.terraform.lock.hcl"
done

for c in "${charts[@]:-}"; do
  [ -n "$c" ] || continue
  echo "== helm lint: $c"
  helm lint "$c" || err "helm lint $c"
done

if [ "$fail" -ne 0 ]; then
  echo "changed-file checks failed" >&2
  exit 1
fi
echo "changed-file checks passed"
