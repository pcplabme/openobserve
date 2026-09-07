#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'emergency-exception-doc-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
governance="${repo_root}/docs/fork-governance.md"
adr="${repo_root}/docs/adr/0001-fork-strategy.md"
template="${repo_root}/.github/pull_request_template.md"
governance_text=$(tr '\n' ' ' <"$governance" | tr -s '[:space:]' ' ')
adr_text=$(tr '\n' ' ' <"$adr" | tr -s '[:space:]' ' ')

for phrase in \
  'second maintainer who is not the patch author' \
  'security PR and deployment record' \
  'one business day after deployment' \
  'aggregate PCPLAB gates must still pass'; do
  grep -Fqi "$phrase" <<<"$governance_text" \
    || fail "governance is missing emergency-exception control: ${phrase}"
done

grep -Fqi 'named in-suite test deferral' <<<"$adr_text" \
  || fail 'ADR does not define the emergency exception as a named in-suite test deferral'
grep -Fqi 'one business day after deployment' <<<"$adr_text" \
  || fail 'ADR does not time-bound emergency test deferrals'

for field in \
  'Deferred test(s):' \
  'Exception approver:' \
  'Exception expiry:' \
  'Post-deployment evidence:'; do
  grep -Fq "$field" "$template" \
    || fail "PR template is missing emergency-exception field: ${field}"
done

printf 'emergency-exception-doc-test: PASS\n'
