#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'fork-release-metadata-test: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local output=$1
  local expected=$2

  grep -Fq -- "$expected" <<<"$output" || fail "expected output to contain: ${expected}"
}

expect_fail() {
  local pattern=$1
  shift

  set +e
  local output
  output=$("$@" 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -ne 0 ]] || fail "expected failure for: $*"
  grep -Fq -- "$pattern" <<<"$output" || fail "expected error containing '${pattern}' for: $*; got: ${output}"
}

expect_pass() {
  set +e
  local output
  output=$("$@" 2>&1)
  local rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || fail "expected success for: $*; got exit ${rc}: ${output}"
  printf '%s' "$output"
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
metadata_script="${repo_root}/scripts/fork-release-metadata.sh"
[[ -x "$metadata_script" ]] || fail "fork-release-metadata.sh not executable: ${metadata_script}"

tmp_root=${TMPDIR:-/tmp}
tmp_dir=$(mktemp -d "${tmp_root}/pcplab-fork-release-metadata.XXXXXX")

cleanup() {
  case "$tmp_dir" in
    "${tmp_root}"/pcplab-fork-release-metadata.*)
      rm -rf -- "$tmp_dir"
      ;;
    *)
      printf 'fork-release-metadata-test: refusing to remove unexpected path: %s\n' "$tmp_dir" >&2
      ;;
  esac
}
trap cleanup EXIT

test_repo="${tmp_dir}/repo"
mkdir -p "$test_repo"
cd "$test_repo"

git init -q -b main
git config user.name 'PCPLAB Test'
git config user.email 'pcplab-test@example.invalid'
git config commit.gpgsign false
git config tag.gpgsign false

# Create a base commit the recorded UPSTREAM_BASE_SHA will point at. The
# metadata script verifies the SHA resolves via `git cat-file -e` so it must
# reference a real local commit.
git commit --allow-empty -qm 'base'
base_sha=$(git rev-parse HEAD)

# Helper: build a release commit that points UPSTREAM_SOURCE_VERSION,
# UPSTREAM_BASE_TYPE, and Cargo.toml version at supplied values, then tag it.
make_release() {
  local tag=$1
  local source_version=$2
  local base_type=$3

  rm -rf .fork Cargo.toml
  mkdir -p .fork
  {
    printf 'UPSTREAM_REPOSITORY=https://github.com/openobserve/openobserve.git\n'
    printf 'UPSTREAM_SOURCE_VERSION=%s\n' "$source_version"
    printf 'UPSTREAM_BASE_SHA=%s\n' "$base_sha"
    printf 'UPSTREAM_BASE_TYPE=%s\n' "$base_type"
    printf 'UPSTREAM_SECURITY_PATCH_SHAS=\n'
    printf '# release marker %s\n' "$tag"
  } >.fork/upstream.env
  printf 'version = "%s"\n' "$source_version" >Cargo.toml
  git add .fork/upstream.env Cargo.toml
  git commit --allow-empty -qm "release ${tag}"
  if git rev-parse --verify --quiet "refs/tags/${tag}" >/dev/null; then
    git tag -d "$tag" >/dev/null
  fi
  git tag -a "$tag" -m "tag ${tag}"
}

# -------------------------------------------------------------------------
# Valid tag grammar + valid metadata: must emit parseable provenance JSON.
# -------------------------------------------------------------------------
make_release v0.93.0-pcplab.1 0.93.0 main-development
valid_output=$(expect_pass env BUILD_TIMESTAMP='2026-08-26T00:00:00Z' SOURCE_URL='https://example.invalid/source' \
  "$metadata_script" v0.93.0-pcplab.1)
jq -e . >/dev/null <<<"$valid_output" || fail "valid release must emit valid JSON"
assert_contains "$valid_output" '"distribution": "PCPLAB OpenObserve OSS fork"'
assert_contains "$valid_output" '"company_release": "v0.93.0-pcplab.1"'
assert_contains "$valid_output" '"fork_sha":'
assert_contains "$valid_output" '"upstream_source_version": "0.93.0"'
assert_contains "$valid_output" '"upstream_base_sha":'
assert_contains "$valid_output" '"upstream_base_type": "main-development"'
assert_contains "$valid_output" '"build_timestamp": "2026-08-26T00:00:00Z"'
assert_contains "$valid_output" '"source": "https://example.invalid/source"'
assert_contains "$valid_output" '"license": "AGPL-3.0"'

# Release-candidate grammar must also be accepted.
make_release v0.93.0-pcplab.2.rc.1 0.93.0 main-development
expect_pass env BUILD_TIMESTAMP='2026-08-26T00:00:00Z' "$metadata_script" v0.93.0-pcplab.2.rc.1 >/dev/null

# -------------------------------------------------------------------------
# Rejected tag grammar: wrong prefix, bad revision, prerelease must be rc.
# -------------------------------------------------------------------------
expect_fail 'release tag must match' "$metadata_script" 'not-a-tag'
expect_fail 'release tag must match' "$metadata_script" '0.93.0-pcplab.1'
expect_fail 'release tag must match' "$metadata_script" 'v0.93.0-pcplab.0'
expect_fail 'release tag must match' "$metadata_script" 'v0.93.0-pcplab.1.beta.1'
expect_fail 'release tag must match' "$metadata_script" 'v0.93.0-pcplab'

# A real release tag that has never been created locally must die because
# `git rev-parse --verify` rejects it.
expect_fail 'does not exist locally' "$metadata_script" v9.99.99-pcplab.1

# -------------------------------------------------------------------------
# Metadata/version mismatch: Cargo.toml version disagrees with metadata.
# -------------------------------------------------------------------------
# Use a clean tree so we control every byte.
force_tag() {
  if git rev-parse --verify --quiet "refs/tags/${1}" >/dev/null; then
    git tag -d "$1" >/dev/null
  fi
}

rm -rf .fork Cargo.toml
mkdir -p .fork
{
  printf 'UPSTREAM_REPOSITORY=https://github.com/openobserve/openobserve.git\n'
  printf 'UPSTREAM_SOURCE_VERSION=0.93.0\n'
  printf 'UPSTREAM_BASE_SHA=%s\n' "$base_sha"
  printf 'UPSTREAM_BASE_TYPE=main-development\n'
  printf 'UPSTREAM_SECURITY_PATCH_SHAS=\n'
  printf '# mismatched marker\n'
} >.fork/upstream.env
printf 'version = "0.94.0"\n' >Cargo.toml
git add .fork/upstream.env Cargo.toml
git commit --allow-empty -qm 'release with mismatched Cargo.toml'
force_tag v0.93.0-pcplab.1
git tag -a v0.93.0-pcplab.1 -m 'mismatch'
expect_fail 'does not match metadata version' "$metadata_script" v0.93.0-pcplab.1

# -------------------------------------------------------------------------
# Invalid base type must be rejected even when version + grammar are valid.
# -------------------------------------------------------------------------
rm -rf .fork Cargo.toml
mkdir -p .fork
{
  printf 'UPSTREAM_REPOSITORY=https://github.com/openobserve/openobserve.git\n'
  printf 'UPSTREAM_SOURCE_VERSION=0.93.0\n'
  printf 'UPSTREAM_BASE_SHA=%s\n' "$base_sha"
  printf 'UPSTREAM_BASE_TYPE=garbage-value\n'
  printf 'UPSTREAM_SECURITY_PATCH_SHAS=\n'
  printf '# bad-type marker\n'
} >.fork/upstream.env
printf 'version = "0.93.0"\n' >Cargo.toml
git add .fork/upstream.env Cargo.toml
git commit --allow-empty -qm 'release with bad base type'
force_tag v0.93.0-pcplab.1
git tag -a v0.93.0-pcplab.1 -m 'bad base type'
expect_fail 'unsupported UPSTREAM_BASE_TYPE' "$metadata_script" v0.93.0-pcplab.1

# -------------------------------------------------------------------------
# release-tag and security-cherry-pick base types must be accepted.
# -------------------------------------------------------------------------
for ok_type in release-tag security-cherry-pick; do
  rm -rf .fork Cargo.toml
  mkdir -p .fork
  {
    printf 'UPSTREAM_REPOSITORY=https://github.com/openobserve/openobserve.git\n'
    printf 'UPSTREAM_SOURCE_VERSION=0.93.0\n'
    printf 'UPSTREAM_BASE_SHA=%s\n' "$base_sha"
    printf 'UPSTREAM_BASE_TYPE=%s\n' "$ok_type"
    printf 'UPSTREAM_SECURITY_PATCH_SHAS=\n'
    printf '# %s marker\n' "$ok_type"
  } >.fork/upstream.env
  printf 'version = "0.93.0"\n' >Cargo.toml
  git add .fork/upstream.env Cargo.toml
  git commit --allow-empty -qm "release with ${ok_type}"
  force_tag v0.93.0-pcplab.1
  git tag -a v0.93.0-pcplab.1 -m "${ok_type}"
  expect_pass env BUILD_TIMESTAMP='2026-08-26T00:00:00Z' "$metadata_script" v0.93.0-pcplab.1 >/dev/null
done

printf 'fork-release-metadata-test: PASS\n'
