#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'pcplab-private-crates-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
shopt -s globstar nullglob
manifests=("${repo_root}"/src/pcplab/**/Cargo.toml)
shopt -u globstar nullglob

for manifest in "${manifests[@]}"; do
  awk '
    /^\[package\]$/ { in_package=1; next }
    /^\[/ { in_package=0 }
    in_package && /^[[:space:]]*publish[[:space:]]*=[[:space:]]*false([[:space:]]*(#.*)?)?$/ { private=1 }
    END { exit !private }
  ' "$manifest" || fail "PCPLAB-owned workspace crate must declare publish = false: ${manifest#"${repo_root}"/}"
done

printf 'pcplab-private-crates-test: PASS (%d manifest(s) audited)\n' "${#manifests[@]}"
