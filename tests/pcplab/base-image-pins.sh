#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'base-image-pins-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
dockerfiles=(
  "${repo_root}/deploy/build/Dockerfile.tag.amd64"
  "${repo_root}/deploy/build/Dockerfile.tag.aarch64"
)

audited=0
for dockerfile in "${dockerfiles[@]}"; do
  [[ -f "$dockerfile" ]] || fail "missing release Dockerfile: $dockerfile"
  syntax=$(head -n 1 "$dockerfile")
  [[ "$syntax" =~ ^#[[:space:]]syntax=docker/dockerfile:1@sha256:[0-9a-f]{64}$ ]] \
    || fail "Dockerfile frontend is not pinned by digest in $(basename "$dockerfile"): $syntax"
  while IFS= read -r line; do
    audited=$((audited + 1))
    image=${line#FROM }
    image=${image%% AS *}
    if ! [[ "$image" =~ @sha256:[0-9a-f]{64}$ ]]; then
      fail "release base image is not pinned by digest in $(basename "$dockerfile"): $image"
    fi
  done < <(grep -E '^FROM ' "$dockerfile")
done

[[ $audited -eq 6 ]] || fail "expected six release build stages, audited $audited"
printf 'base-image-pins-test: PASS (%d release stages audited)\n' "$audited"
