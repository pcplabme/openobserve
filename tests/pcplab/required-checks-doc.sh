#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'required-checks-doc-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
governance="${repo_root}/docs/fork-governance.md"
[[ -f "$governance" ]] || fail "missing governance document"

ruleset=$(awk '
  index($0, "```json") == 1 { capture=1; next }
  capture && index($0, "```") == 1 { exit }
  capture { print }
' "$governance")
jq -e '.name == "Protect PCPLAB main"' <<<"$ruleset" >/dev/null ||
  fail "governance ruleset JSON is missing or invalid"

mapfile -t actual < <(jq -r '
  .rules[]
  | select(.type == "required_status_checks")
  | .parameters.required_status_checks[].context
' <<<"$ruleset" | sort)
expected=(pcplab_contract_tests pcplab_pr_gate)

[[ "${actual[*]}" == "${expected[*]}" ]] ||
  fail "required contexts differ: expected [${expected[*]}], got [${actual[*]}]"

for context in "${expected[@]}"; do
  matches=$(grep -R -l -E "^  ${context}:$" "${repo_root}/.github/workflows"/pcplab-*.yml | wc -l)
  [[ "$matches" == 1 ]] || fail "expected exactly one aggregate job named $context, found $matches"
done

for inherited in unit_tests_summary db_tests_summary api_tests_summary db_schema_version_check; do
  if printf '%s\n' "${actual[@]}" | grep -Fxq "$inherited"; then
    fail "inherited context must not be a permanent PCPLAB ruleset requirement: $inherited"
  fi
done

printf 'required-checks-doc-test: PASS (%s)\n' "${expected[*]}"
