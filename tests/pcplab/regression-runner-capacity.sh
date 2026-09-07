#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'regression-runner-capacity-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflow="${repo_root}/.github/workflows/pcplab-regression.yml"

core_job=$(awk '
  $0 == "  pcplab_regression_core:" { capture=1 }
  capture && $0 != "  pcplab_regression_core:" && /^  [A-Za-z_][A-Za-z0-9_-]*:[[:space:]]*$/ { exit }
  capture { print }
' "$workflow")

[[ -n "$core_job" ]] || fail 'pcplab_regression_core job is missing'
grep -Fq 'CARGO_PROFILE_TEST_DEBUG: "0"' <<<"$core_job" \
  || fail 'core regression does not disable test-profile debug artifacts'
grep -Fq 'ZO_SSRF_ALLOW_LOOPBACK: "false"' <<<"$core_job" \
  || fail 'core regression does not restore the production SSRF default for unit tests'
grep -Fq -- '- name: Free runner disk space' <<<"$core_job" \
  || fail 'core regression does not free runner disk before compilation'
grep -Fq 'sudo rm -rf /usr/share/dotnet /opt/ghc /usr/local/share/boost' <<<"$core_job" \
  || fail 'core regression disk cleanup does not remove preinstalled toolchains'
grep -Fq 'sudo rm -rf "$AGENT_TOOLSDIRECTORY"' <<<"$core_job" \
  || fail 'core regression disk cleanup does not remove the hosted tool cache'

cleanup_line=$(grep -nF -- '- name: Free runner disk space' <<<"$core_job" | cut -d: -f1)
checkout_line=$(grep -nF -- '- name: Checkout repository' <<<"$core_job" | cut -d: -f1)
[[ "$cleanup_line" -lt "$checkout_line" ]] \
  || fail 'core regression disk cleanup must run before checkout and cache restore'
grep -Fq 'fetch-depth: 0' <<<"$core_job" \
  || fail 'core regression checkout does not provide tags required by GIT_VERSION tests'
grep -Fq 'git fetch --force --tags https://github.com/openobserve/openobserve.git' <<<"$core_job" \
  || fail 'core regression does not fetch authoritative upstream tags for GIT_VERSION'
grep -Fq 'git describe --tags --abbrev=0' <<<"$core_job" \
  || fail 'core regression does not fail fast when no version tag is reachable'
grep -Fxq '        run: cargo test --workspace --lib -- --test-threads=1' <<<"$core_job" \
  || fail 'core regression does not serialize tests that share global DB/coordinator state'

printf 'regression-runner-capacity-test: PASS\n'
