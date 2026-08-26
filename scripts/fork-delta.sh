#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/fork-delta.sh [--base <sha>] [--details]

Compare the current tree with the adopted upstream snapshot recorded in
.fork/upstream.env. --details also lists company-only files.
EOF
}

die() {
  printf 'fork-delta: %s\n' "$*" >&2
  exit 1
}

metadata_value() {
  local key=$1
  local value

  value=$(awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print }' "$metadata_file")
  [[ -n "$value" ]] || die "missing ${key} in ${metadata_file}"
  printf '%s\n' "$value"
}

count_lines() {
  awk 'NF { count++ } END { print count + 0 }'
}

sum_numstat() {
  awk '
    $1 == "-" || $2 == "-" { binary++ ; next }
    { added += $1; deleted += $2 }
    END { print added + 0, deleted + 0, binary + 0 }
  '
}

base_sha=""
show_details=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      [[ $# -ge 2 ]] || die "--base requires a commit"
      base_sha=$2
      shift 2
      ;;
    --details)
      show_details=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
done

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "run this script inside a Git repository"
metadata_file="${FORK_METADATA_FILE:-${repo_root}/.fork/upstream.env}"
[[ -f "$metadata_file" ]] || die "metadata file not found: ${metadata_file}"

if [[ -z "$base_sha" ]]; then
  base_sha=$(metadata_value UPSTREAM_BASE_SHA)
fi

git cat-file -e "${base_sha}^{commit}" 2>/dev/null || die \
  "upstream base ${base_sha} is unavailable; fetch full upstream history first"

fork_sha=$(git rev-parse HEAD)
source_version=$(metadata_value UPSTREAM_SOURCE_VERSION)
base_type=$(metadata_value UPSTREAM_BASE_TYPE)

company_files=$(git diff --name-only --diff-filter=A "$base_sha" "$fork_sha")
modified_upstream_files=$(git diff --name-only --diff-filter=BCDMRTUX "$base_sha" "$fork_sha")
company_file_count=$(printf '%s\n' "$company_files" | count_lines)
modified_upstream_count=$(printf '%s\n' "$modified_upstream_files" | count_lines)

read -r total_added total_deleted total_binary < <(
  git diff --numstat "$base_sha" "$fork_sha" | sum_numstat
)
read -r company_added company_deleted company_binary < <(
  git diff --numstat --diff-filter=A "$base_sha" "$fork_sha" | sum_numstat
)

upstream_changed_loc=$((total_added + total_deleted - company_added - company_deleted))
upstream_binary_count=$((total_binary - company_binary))

printf 'Fork Delta Report\n\n'
printf '%-32s %s\n' 'Fork SHA:' "$fork_sha"
printf '%-32s %s\n' 'Upstream Base SHA:' "$base_sha"
printf '%-32s %s\n' 'Upstream Source Version:' "$source_version"
printf '%-32s %s\n' 'Upstream Base Type:' "$base_type"
printf '\n'
printf '%-32s %s\n' 'Company-only files:' "$company_file_count"
printf '%-32s %s\n' 'Modified upstream-owned files:' "$modified_upstream_count"
printf '%-32s %s\n' 'Changed upstream-owned LOC:' "$upstream_changed_loc"
printf '%-32s %s\n' 'Company-owned LOC:' "$company_added"

if (( company_binary > 0 || upstream_binary_count > 0 )); then
  printf '%-32s %s\n' 'Company binary files:' "$company_binary"
  printf '%-32s %s\n' 'Changed upstream binary files:' "$upstream_binary_count"
fi

printf '\nModified upstream-owned files (persistent conflict surface):\n'
if [[ -n "$modified_upstream_files" ]]; then
  printf '%s\n' "$modified_upstream_files" | sed 's/^/  - /'
else
  printf '  (none)\n'
fi

if [[ "$show_details" == true ]]; then
  printf '\nCompany-only files:\n'
  if [[ -n "$company_files" ]]; then
    printf '%s\n' "$company_files" | sed 's/^/  - /'
  else
    printf '  (none)\n'
  fi
fi
