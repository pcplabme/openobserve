#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'upstream-drift-test: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local output=$1
  local expected=$2

  grep -Fq -- "$expected" <<<"$output" || fail "expected output to contain: $expected"
}

assert_not_contains() {
  local output=$1
  local unexpected=$2

  if grep -Fq -- "$unexpected" <<<"$output"; then
    fail "expected output not to contain: $unexpected"
  fi
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
drift_script="${repo_root}/scripts/upstream-drift.sh"
tmp_root=${TMPDIR:-/tmp}
tmp_dir=$(mktemp -d "${tmp_root}/patcharp-upstream-drift.XXXXXX")

cleanup() {
  case "$tmp_dir" in
    "${tmp_root}"/patcharp-upstream-drift.*)
      rm -rf -- "$tmp_dir"
      ;;
    *)
      printf 'upstream-drift-test: refusing to remove unexpected path: %s\n' "$tmp_dir" >&2
      ;;
  esac
}
trap cleanup EXIT

test_repo="${tmp_dir}/repo"
mkdir -p "$test_repo"
cd "$test_repo"

git init -q
git config user.name 'Patcharp Test'
git config user.email 'patcharp-test@example.invalid'
git commit --allow-empty -qm 'base'
base_sha=$(git rev-parse HEAD)

git switch -qc fork
mkdir -p company
printf 'fork\n' >company/collision.txt
printf 'fork only\n' >company/fork-only.txt
git add company
git commit -qm 'add fork-owned files'

git switch -qc upstream "$base_sha"
mkdir -p company
printf 'upstream\n' >company/collision.txt
printf 'upstream only\n' >company/upstream-only.txt
git add company
git commit -qm 'add upstream files'
upstream_sha=$(git rev-parse HEAD)

git switch -q fork
mkdir -p .fork
metadata_file="${test_repo}/.fork/upstream.env"
{
  printf 'UPSTREAM_SOURCE_VERSION=0.0.0\n'
  printf 'UPSTREAM_BASE_SHA=%s\n' "$base_sha"
  printf 'UPSTREAM_BASE_TYPE=main-development\n'
} >"$metadata_file"

output=$(FORK_METADATA_FILE="$metadata_file" "$drift_script" "$upstream_sha")

assert_contains "$output" 'Upstream changes overlapping persistent fork edits: 0'
assert_contains "$output" 'Potential add/add collisions with fork-added files: 1'
assert_contains "$output" 'Potential add/add collision files:'
assert_contains "$output" '  - company/collision.txt'
assert_not_contains "$output" '  - company/fork-only.txt'

printf 'upstream-drift-test: PASS\n'
