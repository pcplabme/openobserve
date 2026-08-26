#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/upstream-drift.sh [upstream-ref]

Compare the adopted upstream base in .fork/upstream.env with an available
upstream ref (default: upstream/main). This script fetches nothing.
EOF
}

die() {
  printf 'upstream-drift: %s\n' "$*" >&2
  exit 1
}

metadata_value() {
  local key=$1
  local value

  value=$(awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print }' "$metadata_file")
  [[ -n "$value" ]] || die "missing ${key} in ${metadata_file}"
  printf '%s\n' "$value"
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi
if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

upstream_ref=${1:-upstream/main}
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "run this script inside a Git repository"
metadata_file="${FORK_METADATA_FILE:-${repo_root}/.fork/upstream.env}"
[[ -f "$metadata_file" ]] || die "metadata file not found: ${metadata_file}"

base_sha=$(metadata_value UPSTREAM_BASE_SHA)
source_version=$(metadata_value UPSTREAM_SOURCE_VERSION)
base_type=$(metadata_value UPSTREAM_BASE_TYPE)

git cat-file -e "${base_sha}^{commit}" 2>/dev/null || die \
  "upstream base ${base_sha} is unavailable; fetch full upstream history first"
git rev-parse --verify --quiet "${upstream_ref}^{commit}" >/dev/null || die \
  "ref ${upstream_ref} is unavailable; configure and fetch the upstream remote first"

latest_sha=$(git rev-parse "${upstream_ref}^{commit}")
if ! git merge-base --is-ancestor "$base_sha" "$latest_sha"; then
  die "recorded base ${base_sha} is not an ancestor of ${upstream_ref}; investigate rewritten or incorrect upstream history"
fi

commits_behind=$(git rev-list --count "${base_sha}..${latest_sha}")
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

git diff --name-only "$base_sha" "$latest_sha" | sort -u >"$tmp_dir/upstream-files"
git diff --name-only --diff-filter=BCDMRTUX "$base_sha" HEAD | sort -u >"$tmp_dir/fork-modified-files"
comm -12 "$tmp_dir/upstream-files" "$tmp_dir/fork-modified-files" >"$tmp_dir/overlap-files"

changed_count=$(awk 'NF { count++ } END { print count + 0 }' "$tmp_dir/upstream-files")
overlap_count=$(awk 'NF { count++ } END { print count + 0 }' "$tmp_dir/overlap-files")
migration_count=$(awk '/^src\/infra\/src\/table\/migration\// { count++ } END { print count + 0 }' "$tmp_dir/upstream-files")
dependency_count=$(awk '
  /(^|\/)(Cargo\.toml|Cargo\.lock|package\.json|package-lock\.json|deny\.toml)$/ { count++ }
  END { print count + 0 }
' "$tmp_dir/upstream-files")
workflow_count=$(awk '/^\.github\/workflows\// { count++ } END { print count + 0 }' "$tmp_dir/upstream-files")

printf 'Upstream Drift Report\n\n'
printf '%-31s %s\n' 'Current upstream base:' "$base_sha"
printf '%-31s %s\n' 'Latest upstream SHA:' "$latest_sha"
printf '%-31s %s\n' 'Upstream source version:' "$source_version"
printf '%-31s %s\n' 'Upstream base type:' "$base_type"
printf '%-31s %s\n' 'Commits behind:' "$commits_behind"
printf '%-31s %s\n' 'Changed files upstream:' "$changed_count"

printf '\nChanged areas:\n'
areas_found=false
if grep -Eq '^(src/.*\.(rs|toml)|Cargo\.(toml|lock)|build\.rs$)' "$tmp_dir/upstream-files"; then
  printf '  - Rust backend\n'
  areas_found=true
fi
if grep -Eq '^src/infra/src/table/migration/|^src/config/src/config\.rs$' "$tmp_dir/upstream-files"; then
  printf '  - DB migrations/schema version\n'
  areas_found=true
fi
if grep -Eq '^(web/|src/web/)' "$tmp_dir/upstream-files"; then
  printf '  - Frontend/web assets\n'
  areas_found=true
fi
if grep -Eq '(^|/)(Cargo\.toml|Cargo\.lock|package\.json|package-lock\.json|deny\.toml)$' "$tmp_dir/upstream-files"; then
  printf '  - Dependencies\n'
  areas_found=true
fi
if grep -Eq '^\.github/' "$tmp_dir/upstream-files"; then
  printf '  - GitHub automation/CI\n'
  areas_found=true
fi
if grep -Eq '(^|/)(auth|authz|users?)(/|\.|_)|^src/enterprise/|^web/src/enterprise/' "$tmp_dir/upstream-files"; then
  printf '  - Authentication, authorization, users, or edition boundaries\n'
  areas_found=true
fi
if [[ "$areas_found" == false ]]; then
  printf '  (none)\n'
fi

printf '\nPotential risk indicators:\n'
printf '  - Database migration/schema files changed: %s\n' "$migration_count"
printf '  - Dependency manifests/locks changed: %s\n' "$dependency_count"
printf '  - Workflow files changed: %s\n' "$workflow_count"
printf '  - Upstream changes overlapping persistent fork edits: %s\n' "$overlap_count"

if (( overlap_count > 0 )); then
  printf '\nOverlapping files (likely conflict/retest hotspots):\n'
  sed 's/^/  - /' "$tmp_dir/overlap-files"
fi

printf '\nAutomation has not merged or modified any branch. A maintainer must decide whether to sync.\n'
