#!/usr/bin/env bash

set -euo pipefail

script_name=$(basename "$0")

usage() {
  cat <<EOF
Usage: ${script_name} [test-name]

Discover tests/patcharp/*.sh and execute each script in a fresh subshell.
Report per-test PASS/FAIL and exit non-zero if any test fails.

If test-name is supplied, only the matching basename (with or without the
'.sh' suffix) is run; otherwise every discovered test is executed exactly
once.
EOF
}

die() {
  printf '%s: %s\n' "$script_name" "$*" >&2
  exit 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tests_dir="${repo_root}/tests/patcharp"
[[ -d "$tests_dir" ]] || die "tests directory not found: ${tests_dir}"

selector=${1:-}

shopt -s nullglob
candidates=("$tests_dir"/*.sh)
shopt -u nullglob

if [[ ${#candidates[@]} -eq 0 ]]; then
  die "no tests found under ${tests_dir}"
fi

selected=()
if [[ -n "$selector" ]]; then
  for path in "${candidates[@]}"; do
    base=$(basename "$path")
    if [[ "$base" == "$selector" || "$base" == "${selector}.sh" ]]; then
      selected+=("$path")
    fi
  done
  if [[ ${#selected[@]} -eq 0 ]]; then
    printf '%s: requested test not found: %s\n' "$script_name" "$selector" >&2
    printf '%s: available tests:\n' "$script_name" >&2
    for path in "${candidates[@]}"; do
      printf '  - %s\n' "$(basename "$path")" >&2
    done
    exit 1
  fi
else
  selected=("${candidates[@]}")
fi

tmp_root=${TMPDIR:-/tmp}
work_root=$(mktemp -d "${tmp_root}/patcharp-contract.XXXXXX")

cleanup() {
  case "$work_root" in
    "${tmp_root}"/patcharp-contract.*)
      rm -rf -- "$work_root"
      ;;
    *)
      printf '%s: refusing to remove unexpected path: %s\n' "$script_name" "$work_root" >&2
      ;;
  esac
}
trap cleanup EXIT

printf '%s: executing %d test(s) under tests/patcharp\n\n' "$script_name" "${#selected[@]}"

passed=0
failed=0
order=0
for path in "${selected[@]}"; do
  order=$((order + 1))
  base=$(basename "$path")
  log="${work_root}/${order}.${base}.log"
  set +e
  bash "$path" >"$log" 2>&1
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    printf '  [%02d] PASS  %s\n' "$order" "$base"
    passed=$((passed + 1))
  else
    printf '  [%02d] FAIL  %s  (exit %d)\n' "$order" "$base" "$rc"
    if [[ -s "$log" ]]; then
      sed 's/^/        | /' "$log"
    fi
    failed=$((failed + 1))
  fi
done

printf '\n%s: %d passed, %d failed (total %d)\n' "$script_name" "$passed" "$failed" "${#selected[@]}"

if (( failed > 0 )); then
  exit 1
fi
