#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'product-smoke-wiring-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
smoke="${repo_root}/scripts/pcplab-product-smoke.sh"
regression="${repo_root}/.github/workflows/pcplab-regression.yml"
release="${repo_root}/.github/workflows/pcplab-release.yml"

[[ -x "$smoke" ]] || fail "product smoke script is missing or not executable"

for contract in healthz '_json' 'v1/metrics' 'prometheus/api/v1/query' 'v1/traces' '_search?type=traces' dashboards; do
  grep -Fq -- "$contract" "$smoke" || fail "product smoke omits contract: $contract"
done

grep -Fq 'bash scripts/pcplab-product-smoke.sh' "$regression" \
  || fail "regression workflow does not execute the product smoke"
grep -Fq 'bash scripts/pcplab-product-smoke.sh' "$release" \
  || fail "release workflow does not execute the product smoke against the produced image"

grep -Fq -- '--fail-with-body' "$smoke" \
  || fail "product smoke must preserve failing API response diagnostics"

printf 'product-smoke-wiring-test: PASS\n'
