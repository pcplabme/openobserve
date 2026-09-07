#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'upstream-notices-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
metadata_file="${repo_root}/.fork/upstream.env"
about="${repo_root}/web/src/views/About.vue"
notice="${repo_root}/web/src/pcplab/components/PcplabForkNotice.vue"
build_metadata="${repo_root}/src/pcplab/build.rs"

[[ -f "$notice" ]] || fail 'missing PCPLAB-owned About-page fork notice'
grep -Fq 'PcplabForkNotice' "$about" \
  || fail 'About page does not render the PCPLAB fork notice'
grep -Fq 'raw(license)' "$notice" \
  || fail 'fork notice does not render the compiled license identifier'
grep -Fq 'PCPLAB_BUILD_LICENSE", "AGPL-3.0"' "$build_metadata" \
  || fail 'compiled fork license is not fixed to AGPL-3.0'
grep -Fq 'pcplab_fork' "$notice" \
  || fail 'fork notice is not driven by authenticated build metadata'

base_sha=$(awk -F= '$1 == "UPSTREAM_BASE_SHA" { print $2 }' "$metadata_file")
[[ "$base_sha" =~ ^[0-9a-f]{40}$ ]] || fail 'invalid UPSTREAM_BASE_SHA'
git -C "$repo_root" cat-file -e "${base_sha}^{commit}" \
  || fail 'recorded upstream base is unavailable'
git -C "$repo_root" diff --quiet "$base_sha" -- LICENSE \
  || fail 'upstream AGPL LICENSE was modified by the fork'

printf 'upstream-notices-test: PASS\n'
