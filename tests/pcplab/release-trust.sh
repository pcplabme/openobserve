#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'release-trust-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
release="${repo_root}/.github/workflows/pcplab-release.yml"

grep -Fq 'tags: ["v*-pcplab.*"]' "$release" \
  || fail "release trigger is not restricted to PCPLAB tags"
grep -Fq 'IMAGE_REPOSITORY: patcharp/openobserve' "$release" \
  || fail "release must publish through the configured Docker Hub repository"
if grep -qE '^[[:space:]]*(pull_request|pull_request_target|workflow_dispatch):' "$release"; then
  fail "release exposes an untrusted or non-tag publication trigger"
fi

[[ $(grep -c 'uses: docker/build-push-action@' "$release") -eq 1 ]] \
  || fail "release must build each matrix candidate exactly once"
grep -Fq 'push-by-digest=true' "$release" \
  || fail "candidate image is not pushed without a version tag"
grep -Fq 'docker pull "docker.io/$IMAGE_REPOSITORY@$DIGEST"' "$release" \
  || fail "validation does not pull the exact pushed digest"
[[ $(grep -c 'imagetools inspect "docker.io/$IMAGE_REPOSITORY:' "$release") -eq 3 ]] \
  || fail "version tag must be checked before build, before publish, and after publish"
grep -Fq 'Published manifest does not reference validated $arch digest $digest' "$release" \
  || fail "release does not assert the published manifest references both validated digests"
if grep -qE 'cache-(from|to):[[:space:]]*type=gha' "$release"; then
  fail "release builds must not consume or write mutable GitHub Actions caches"
fi
[[ $(grep -c 'driver-opts: image=moby/buildkit:.*@sha256:' "$release") -eq 3 ]] \
  || fail "every release BuildKit instance must use the same digest-pinned driver image"

validate_line=$(grep -n '^  pcplab_release_validate:' "$release" | cut -d: -f1)
precheck_line=$(grep -n '^  pcplab_release_precheck:' "$release" | cut -d: -f1)
validate_block=$(sed -n "${validate_line},$((precheck_line - 1))p" "$release")
if grep -q 'environment: release-dockerhub' <<<"$validate_block"; then
  fail "secret-free release validation must run before environment approval"
fi

build_line=$(grep -n 'Build and push untagged candidate by digest' "$release" | cut -d: -f1)
smoke_line=$(grep -n 'Smoke-test produced image' "$release" | cut -d: -f1)
scan_line=$(grep -n 'Scan image vulnerabilities' "$release" | cut -d: -f1)
publish_line=$(grep -n 'docker buildx imagetools create' "$release" | cut -d: -f1)
[[ $build_line -lt $smoke_line && $smoke_line -lt $scan_line && $scan_line -lt $publish_line ]] \
  || fail "release build/smoke/scan/publish ordering is unsafe"

if grep -Eq '(^|[^[:alnum:]_-])latest([^[:alnum:]_-]|$)' "$release"; then
  fail "release workflow must never publish or reference latest"
fi

printf 'release-trust-test: PASS\n'
