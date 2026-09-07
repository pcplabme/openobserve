#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'fork-build-metadata-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
manifest="${repo_root}/src/pcplab/Cargo.toml"
metadata="${repo_root}/src/pcplab/src/build_metadata/mod.rs"
build_script="${repo_root}/src/pcplab/build.rs"
status="${repo_root}/src/api/management/src/request/status/mod.rs"
release="${repo_root}/.github/workflows/pcplab-release.yml"

[[ -f "$manifest" ]] || fail 'missing PCPLAB-owned build metadata crate'
[[ -f "$metadata" ]] || fail 'missing typed build metadata module'
[[ -f "$build_script" ]] || fail 'missing compile-time provenance validator'

grep -Fq 'name = "openobserve-pcplab"' "$manifest" \
  || fail 'PCPLAB crate has the wrong package name'
grep -Fq 'pub struct ForkBuildMetadata' "$metadata" \
  || fail 'typed fork build metadata is missing'
grep -Fq "pub docker_image: Option<&'static str>" "$metadata" \
  || fail 'runtime metadata omits the immutable Docker image identity'
[[ $(grep -c '^serde\.workspace = true$' "$manifest") -eq 1 ]] \
  || fail 'PCPLAB metadata crate must reuse only the reviewed workspace serde dependency'
grep -Fq 'pcplab_fork:' "$status" \
  || fail 'authenticated config does not expose PCPLAB fork metadata'

bootstrap_block=$(sed -n '/struct ConfigBootstrapResponse {/,/^}/p' "$status")
if grep -Fq 'pcplab_fork:' <<<"$bootstrap_block"; then
  fail 'fork provenance must not be added to the anonymous bootstrap payload'
fi

for key in PCPLAB_RELEASE PCPLAB_FORK_SHA PCPLAB_BUILD_TIMESTAMP PCPLAB_SOURCE_URL; do
  grep -Fq "${key}=" "$release" \
    || fail "release build does not pass ${key} to the container build"
done

if grep -Rq 'DOCKERHUB_' \
  "${repo_root}/deploy/build/Dockerfile.tag.amd64" \
  "${repo_root}/deploy/build/Dockerfile.tag.aarch64"; then
  fail 'Docker Hub credentials must never enter Docker build arguments or layers'
fi

for dockerfile in \
  "${repo_root}/deploy/build/Dockerfile.tag.amd64" \
  "${repo_root}/deploy/build/Dockerfile.tag.aarch64"; do
  for key in PCPLAB_RELEASE PCPLAB_FORK_SHA PCPLAB_BUILD_TIMESTAMP PCPLAB_SOURCE_URL; do
    grep -Fq "ARG ${key}" "$dockerfile" \
      || fail "$(basename "$dockerfile") does not declare ${key}"
  done
done

printf 'fork-build-metadata-test: PASS\n'
