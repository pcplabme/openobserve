#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'release-provenance-retention-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
release="${repo_root}/.github/workflows/pcplab-release.yml"

grep -Fq 'contents: write' "$release" \
  || fail 'publish job cannot create the durable GitHub Release record'
grep -Fq 'gh release create' "$release" \
  || fail 'release evidence is not retained in a GitHub Release'
grep -Fq -- '--draft' "$release" \
  || fail 'durable release evidence is not staged before Docker publication'
grep -Fq 'gh release edit "$RELEASE_TAG" --draft=false' "$release" \
  || fail 'GitHub Release is not finalized after Docker publication'
gh_repo_count=$(grep -Fc 'GH_REPO: ${{ github.repository }}' "$release")
[[ $gh_repo_count -eq 2 ]] \
  || fail 'both checkout-free GitHub Release steps must identify the repository through GH_REPO'
grep -Fq "GitHub Release immutability check failed closed" "$release" \
  || fail 'GitHub Release existence lookup must distinguish not-found from infrastructure failures'
grep -Fq 'provenance.json' "$release" \
  || fail 'provenance manifest is not retained'
grep -Fq 'SOURCE.md' "$release" \
  || fail 'durable corresponding-source pointer is missing'
grep -Fq 'SHA256SUMS' "$release" \
  || fail 'release evidence has no checksum manifest'
grep -Fq 'pcplab_fork' "$release" \
  || fail 'runtime fork metadata is not checked against provenance.json'
grep -Fq 'ai.pcplab.release_channel' "$release" \
  || fail 'OCI labels omit the release channel'
grep -Fq 'ai.pcplab.docker_image' "$release" \
  || fail 'OCI labels omit the immutable Docker image identity'

if grep -Fq -- '--clobber' "$release"; then
  fail 'release assets must not silently overwrite immutable evidence'
fi

stage_line=$(grep -n 'Stage durable provenance and compliance evidence' "$release" | cut -d: -f1)
publish_line=$(grep -n 'docker buildx imagetools create' "$release" | cut -d: -f1)
finalize_line=$(grep -n 'Finalize durable GitHub Release' "$release" | cut -d: -f1)
[[ $stage_line -lt $publish_line && $publish_line -lt $finalize_line ]] \
  || fail 'durable evidence must be staged before Docker publication and finalized afterward'

printf 'release-provenance-retention-test: PASS\n'
