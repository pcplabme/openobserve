#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'fork-delta-test: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local output=$1
  local expected=$2

  grep -Fq -- "$expected" <<<"$output" || fail "expected output to contain: ${expected}"
}

assert_not_contains() {
  local output=$1
  local unexpected=$2

  if grep -Fq -- "$unexpected" <<<"$output"; then
    fail "expected output not to contain: ${unexpected}"
  fi
}

strip_indent() {
  sed 's/^[[:space:]]*//'
}

extract_number() {
  local prefix=$1
  local output=$2

  awk -v prefix="$prefix" '
    $0 ~ prefix {
      sub(prefix, "")
      sub(/^[[:space:]]+/, "")
      sub(/[^0-9].*/, "")
      print
      exit
    }
  ' <<<"$output"
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
delta_script="${repo_root}/scripts/fork-delta.sh"
[[ -x "$delta_script" ]] || fail "fork-delta.sh not executable: ${delta_script}"

tmp_root=${TMPDIR:-/tmp}
tmp_dir=$(mktemp -d "${tmp_root}/patcharp-fork-delta.XXXXXX")

cleanup() {
  case "$tmp_dir" in
    "${tmp_root}"/patcharp-fork-delta.*)
      rm -rf -- "$tmp_dir"
      ;;
    *)
      printf 'fork-delta-test: refusing to remove unexpected path: %s\n' "$tmp_dir" >&2
      ;;
  esac
}
trap cleanup EXIT

test_repo="${tmp_dir}/repo"
mkdir -p "$test_repo"
cd "$test_repo"

git init -q -b main
git config user.name 'Patcharp Test'
git config user.email 'patcharp-test@example.invalid'
git config commit.gpgsign false

git commit --allow-empty -qm 'base'
mkdir -p upstream
printf 'upstream original line\n' >upstream/owned.txt
git add upstream/owned.txt
git commit -qm 'upstream: add owned.txt'
base_sha=$(git rev-parse HEAD)

# Switch to a fork branch where we modify the upstream-owned file and add a
# company-owned file. The base_sha above becomes the recorded upstream base.
git checkout -qb fork
mkdir -p company
printf 'fork company line\n' >company/fork.txt
printf 'fork modified line\n' >upstream/owned.txt
git add company/fork.txt upstream/owned.txt
git commit -qm 'fork: company-only file plus modified upstream-owned file'

mkdir -p .fork
metadata_file="${test_repo}/.fork/upstream.env"
{
  printf 'UPSTREAM_REPOSITORY=https://github.com/openobserve/openobserve.git\n'
  printf 'UPSTREAM_SOURCE_VERSION=0.0.0\n'
  printf 'UPSTREAM_BASE_SHA=%s\n' "$base_sha"
  printf 'UPSTREAM_BASE_TYPE=main-development\n'
  printf 'UPSTREAM_SECURITY_PATCH_SHAS=\n'
} >"$metadata_file"

output=$(FORK_METADATA_FILE="$metadata_file" "$delta_script")
details_output=$(FORK_METADATA_FILE="$metadata_file" "$delta_script" --details)

extract_field() {
  local label=$1
  local source=$2
  awk -v label="$label" '
    {
      stripped = $0
      sub(/^[[:space:]]+/, "", stripped)
      n = split(stripped, parts, ":")
      head = parts[1]
      sub(/[[:space:]]+$/, "", head)
      if (head == label) {
        sub(/^[^:]*:[[:space:]]+/, "", stripped)
        sub(/[[:space:]]+$/, "", stripped)
        print stripped
        exit
      }
    }
  ' <<<"$source"
}

assert_contains "$output" "Fork SHA:"

recorded_base=$(extract_field "Upstream Base SHA" "$output")
[[ "$recorded_base" == "$base_sha" ]] || fail "expected Upstream Base SHA ${base_sha}, got '${recorded_base}'"

recorded_version=$(extract_field "Upstream Source Version" "$output")
[[ "$recorded_version" == "0.0.0" ]] || fail "expected Upstream Source Version 0.0.0, got '${recorded_version}'"

recorded_type=$(extract_field "Upstream Base Type" "$output")
[[ "$recorded_type" == "main-development" ]] || fail "expected Upstream Base Type main-development, got '${recorded_type}'"

company_count=$(extract_number 'Company-only files:' "$output")
[[ "$company_count" == "1" ]] || fail "expected 1 company-only file, got '${company_count}'"

modified_count=$(extract_number 'Modified upstream-owned files:' "$output")
[[ "$modified_count" == "1" ]] || fail "expected 1 modified upstream file, got '${modified_count}'"

assert_contains "$output" 'Modified upstream-owned files (persistent conflict surface):'
assert_contains "$output" '  - upstream/owned.txt'
assert_not_contains "$output" '  - company/fork.txt'

# --details must include the company-only file list (default output omits it).
assert_contains "$details_output" 'Company-only files:'
assert_contains "$details_output" '  - company/fork.txt'
assert_contains "$details_output" '  - upstream/owned.txt'

# upstream-owned LOC must strictly exceed zero because owned.txt was modified.
changed_loc=$(extract_number 'Changed upstream-owned LOC:' "$output")
if ! [[ "$changed_loc" =~ ^[0-9]+$ ]] || (( changed_loc == 0 )); then
  fail "expected positive upstream-owned LOC delta, got '${changed_loc}'"
fi

# branch with no company-only delta still reports zero (regression guard for
# the synthetic empty-payload case).
git checkout -qb fork-clean
git checkout -q fork -- company/fork.txt
git rm -q -- company/fork.txt
git commit -qm 'fork: remove company-only file'
clean_output=$(FORK_METADATA_FILE="$metadata_file" "$delta_script")
clean_company=$(extract_number 'Company-only files:' "$clean_output")
[[ "$clean_company" == "0" ]] || fail "expected 0 company-only files on clean branch, got '${clean_company}'"

# Script must refuse to run when the recorded base SHA cannot be resolved.
git checkout -qb fork-bad
missing_sha=$(printf '%040d\n' 1)
bad_metadata="${test_repo}/.fork/upstream.env"
{
  printf 'UPSTREAM_REPOSITORY=https://github.com/openobserve/openobserve.git\n'
  printf 'UPSTREAM_SOURCE_VERSION=0.0.0\n'
  printf 'UPSTREAM_BASE_SHA=%s\n' "$missing_sha"
  printf 'UPSTREAM_BASE_TYPE=main-development\n'
  printf 'UPSTREAM_SECURITY_PATCH_SHAS=\n'
} >"$bad_metadata"
set +e
bad_output=$(FORK_METADATA_FILE="$bad_metadata" "$delta_script" 2>&1)
bad_rc=$?
set -e
[[ "$bad_rc" -ne 0 ]] || fail "fork-delta must fail on unknown base SHA, got exit 0"
assert_contains "$bad_output" "upstream base ${missing_sha} is unavailable"

printf 'fork-delta-test: PASS\n'
