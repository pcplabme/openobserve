#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'security-branch-convention-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
governance="${repo_root}/docs/fork-governance.md"
adr="${repo_root}/docs/adr/0001-fork-strategy.md"
workflow_doc="${repo_root}/docs/multi-agent-workflow.md"
contract="${repo_root}/.github/workflows/pcplab-contract.yml"

for document in "$governance" "$adr" "$workflow_doc"; do
  grep -Fq 'sync/security-YYYY-MM-DD-<topic>' "$document" \
    || fail "dated security branch convention missing from ${document#"${repo_root}/"}"
  if grep -Fq 'sync/security-<CVE-or-topic>' "$document"; then
    fail "obsolete undated security branch convention remains in ${document#"${repo_root}/"}"
  fi
done

grep -Fq "startsWith(github.head_ref, 'sync/security-')" "$contract" \
  || fail 'documented dated prefix no longer matches the contract workflow predicate'

printf 'security-branch-convention-test: PASS\n'
