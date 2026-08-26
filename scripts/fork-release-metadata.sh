#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/fork-release-metadata.sh <release-tag>

Emit the provenance JSON for an existing Patcharp release tag. Set
BUILD_TIMESTAMP to the artifact build time and SOURCE_URL to the retained
Corresponding Source location when the defaults are not appropriate.
EOF
}

die() {
  printf 'fork-release-metadata: %s\n' "$*" >&2
  exit 1
}

metadata_value() {
  local key=$1
  local allow_empty=${2:-false}
  local value

  value=$(awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print }' <<<"$metadata_contents")
  if [[ "$allow_empty" != true && -z "$value" ]]; then
    die "missing ${key} in ${release_tag}:.fork/upstream.env"
  fi
  printf '%s\n' "$value"
}

if [[ $# -ne 1 || ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  [[ $# -eq 1 ]] && exit 0
  exit 2
fi

release_tag=$1
if [[ ! "$release_tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-patcharp\.[1-9][0-9]*(\.rc\.[1-9][0-9]*)?$ ]]; then
  die "release tag must match v<upstream>-patcharp.<revision>[.rc.<revision>]"
fi
tag_source_version=${BASH_REMATCH[1]}

git rev-parse --show-toplevel >/dev/null 2>&1 || die "run this script inside a Git repository"
fork_sha=$(git rev-parse --verify "${release_tag}^{commit}" 2>/dev/null) || die \
  "release tag ${release_tag} does not exist locally"
metadata_contents=$(git show "${release_tag}:.fork/upstream.env" 2>/dev/null) || die \
  "release tag ${release_tag} does not contain .fork/upstream.env"
source_version=$(metadata_value UPSTREAM_SOURCE_VERSION)
base_sha=$(metadata_value UPSTREAM_BASE_SHA)
base_type=$(metadata_value UPSTREAM_BASE_TYPE)
security_patch_shas=$(metadata_value UPSTREAM_SECURITY_PATCH_SHAS true)

[[ "$tag_source_version" == "$source_version" ]] || die \
  "tag source version ${tag_source_version} does not match metadata version ${source_version}"
git cat-file -e "${base_sha}^{commit}" 2>/dev/null || die \
  "upstream base ${base_sha} is unavailable; fetch full upstream history first"

manifest_version=$(git show "${release_tag}:Cargo.toml" | awk -F'"' '/^version = "/ { print $2; exit }')
[[ "$manifest_version" == "$source_version" ]] || die \
  "Cargo.toml version ${manifest_version} does not match metadata version ${source_version}"

case "$base_type" in
  release-tag|main-development|security-cherry-pick) ;;
  *) die "unsupported UPSTREAM_BASE_TYPE: ${base_type}" ;;
esac

build_timestamp=${BUILD_TIMESTAMP:-$(date -u +'%Y-%m-%dT%H:%M:%SZ')}
source_url=${SOURCE_URL:-https://github.com/patcharp/openobserve/tree/${fork_sha}}

cat <<EOF
{
  "distribution": "Patcharp OpenObserve OSS fork",
  "company_release": "${release_tag}",
  "fork_sha": "${fork_sha}",
  "upstream_repository": "https://github.com/openobserve/openobserve",
  "upstream_source_version": "${source_version}",
  "upstream_base_sha": "${base_sha}",
  "upstream_base_type": "${base_type}",
  "upstream_security_patch_shas": "${security_patch_shas}",
  "build_timestamp": "${build_timestamp}",
  "license": "AGPL-3.0",
  "source": "${source_url}"
}
EOF
