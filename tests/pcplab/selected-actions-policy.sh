#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'selected-actions-policy-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
policy="${repo_root}/.github/pcplab-actions-policy.json"
workflow_dir="${repo_root}/.github/workflows"
[[ -f "$policy" ]] || fail "missing selected-actions policy"
jq -e '
  .github_owned_allowed == false and
  .verified_allowed == false and
  (.patterns_allowed | type == "array" and length > 0)
' "$policy" >/dev/null || fail "policy must disable broad GitHub-owned and verified-publisher access"

mapfile -t direct < <(
  grep -hE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*' \
    "$workflow_dir"/pcplab-*.yml "$workflow_dir"/upstream-drift.yml \
    | sed -E 's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*([^[:space:]#]+).*/\2/' \
    | grep -vE '^(\./|docker://)' \
    | sort -u
)
mapfile -t allowed < <(jq -r '.patterns_allowed[]' "$policy" | sort -u)

for reference in "${direct[@]}"; do
  printf '%s\n' "${allowed[@]}" | grep -Fxq "$reference" \
    || fail "direct workflow action is absent from selected policy: $reference"
done

# Trivy v0.36.0 is a composite action. GitHub applies the selected-actions
# policy to these nested entrypoints too, so they remain explicit and pinned.
nested=(
  "actions/cache@27d5ce7f107fe9357f9df03efb73ab90386fccae"
  "aquasecurity/setup-trivy@3fb12ec12f41e471780db15c232d5dd185dcb514"
)
for reference in "${nested[@]}"; do
  printf '%s\n' "${allowed[@]}" | grep -Fxq "$reference" \
    || fail "nested Trivy action is absent from selected policy: $reference"
done

expected_count=$((${#direct[@]} + ${#nested[@]}))
[[ ${#allowed[@]} -eq $expected_count ]] \
  || fail "policy has unexpected entries: expected $expected_count, found ${#allowed[@]}"

for reference in "${allowed[@]}"; do
  [[ "$reference" =~ ^[^/@]+/[^/@]+@[0-9a-f]{40}$ ]] \
    || fail "policy reference is not an exact owner/repository@SHA: $reference"
done

printf 'selected-actions-policy-test: PASS (%d direct, %d nested actions)\n' \
  "${#direct[@]}" "${#nested[@]}"
