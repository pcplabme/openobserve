#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'outer-gate-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
contract="${repo_root}/.github/workflows/pcplab-contract.yml"
release="${repo_root}/.github/workflows/pcplab-release.yml"

grep -Fq 'uses: ./.github/workflows/pcplab-regression.yml' "$contract" \
  || fail "outer contract gate does not call the reusable regression workflow"
grep -Fq 'uses: ./.github/workflows/pcplab-security.yml' "$contract" \
  || fail "outer contract gate does not call the reusable security workflow"
grep -Fq "startsWith(github.head_ref, 'sync/upstream-')" "$contract" \
  || fail "sync/upstream branches do not require the nested regression"
grep -Fq "startsWith(github.head_ref, 'sync/security-')" "$contract" \
  || fail "sync/security branches do not require the nested regression"

for nested_job in pcplab_contract_regression pcplab_contract_security; do
  awk -v job="$nested_job" '
    $0 == "  pcplab_contract_tests:" { aggregate=1; next }
    aggregate && $0 == "      - " job { found=1 }
    END { exit !found }
  ' "$contract" || fail "pcplab_contract_tests does not wait for $nested_job"
done

grep -Fq 'required=(pcplab_pr_gate pcplab_contract_tests)' "$release" \
  || fail "release does not require the two stable outer checks on the tagged SHA"

printf 'outer-gate-test: PASS\n'
