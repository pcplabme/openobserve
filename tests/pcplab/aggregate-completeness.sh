#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'aggregate-completeness-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflow_dir="${repo_root}/.github/workflows"

declare -A aggregates=(
  [pcplab-pr.yml]=pcplab_pr_gate
  [pcplab-contract.yml]=pcplab_contract_tests
  [pcplab-regression.yml]=pcplab_regression_tests
  [pcplab-security.yml]=pcplab_security_gate
)

for workflow in "${!aggregates[@]}"; do
  file="${workflow_dir}/${workflow}"
  aggregate=${aggregates[$workflow]}
  [[ -f "$file" ]] || fail "missing $workflow"

  mapfile -t jobs < <(awk '
    /^jobs:[[:space:]]*$/ { in_jobs=1; next }
    in_jobs && /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ {
      job=$0
      sub(/^  /, "", job)
      sub(/:[[:space:]]*$/, "", job)
      print job
      next
    }
    in_jobs && /^[^[:space:]]/ { in_jobs=0 }
  ' "$file")
  (( ${#jobs[@]} > 1 )) || fail "$workflow must declare multiple jobs"

  mapfile -t needs < <(awk -v aggregate="$aggregate" '
    $0 == "  " aggregate ":" { in_aggregate=1; next }
    in_aggregate && /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ { exit }
    in_aggregate && /^    needs:[[:space:]]*$/ { in_needs=1; next }
    in_aggregate && in_needs && /^      - / {
      need=$0
      sub(/^      - /, "", need)
      print need
      next
    }
    in_aggregate && in_needs && /^    [A-Za-z_-]+:/ { in_needs=0 }
  ' "$file")
  (( ${#needs[@]} > 0 )) || fail "$workflow aggregate $aggregate has no block-form needs list"

  for job in "${jobs[@]}"; do
    [[ "$job" == "$aggregate" ]] && continue
    found=false
    for need in "${needs[@]}"; do
      if [[ "$need" == "$job" ]]; then
        found=true
        break
      fi
    done
    $found || fail "$workflow job $job is not gated by $aggregate"
  done
done

printf 'aggregate-completeness-test: PASS (4 workflow aggregates audited)\n'
