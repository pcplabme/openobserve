#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/fork-release-metadata.sh <release-tag>

Emit the provenance JSON for an existing PCPLAB release tag. Set
BUILD_TIMESTAMP to the artifact build time when generating release evidence.
Corresponding Source is always pinned to the exact fork commit.
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
if [[ ! "$release_tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)-pcplab\.[1-9][0-9]*(\.rc\.[1-9][0-9]*)?$ ]]; then
  die "release tag must match v<upstream>-pcplab.<revision>[.rc.<revision>]"
fi
tag_source_version=${BASH_REMATCH[1]}
if [[ "$release_tag" == *.rc.* ]]; then
  release_channel=release-candidate
else
  release_channel=release
fi

git rev-parse --show-toplevel >/dev/null 2>&1 || die "run this script inside a Git repository"
fork_sha=$(git rev-parse --verify "${release_tag}^{commit}" 2>/dev/null) || die \
  "release tag ${release_tag} does not exist locally"
metadata_contents=$(git show "${release_tag}:.fork/upstream.env" 2>/dev/null) || die \
  "release tag ${release_tag} does not contain .fork/upstream.env"
source_version=$(metadata_value UPSTREAM_SOURCE_VERSION)
base_sha=$(metadata_value UPSTREAM_BASE_SHA)
base_type=$(metadata_value UPSTREAM_BASE_TYPE)
security_patch_shas=$(metadata_value UPSTREAM_SECURITY_PATCH_SHAS true)
security_advisories=$(metadata_value UPSTREAM_SECURITY_ADVISORIES true)

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
[[ "$build_timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
  || die "BUILD_TIMESTAMP must be an RFC 3339 UTC timestamp"
[[ "$(date -u -d "$build_timestamp" +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true)" == "$build_timestamp" ]] \
  || die "BUILD_TIMESTAMP is not a valid UTC date/time"
expected_source_url=https://github.com/pcplabme/openobserve/tree/${fork_sha}
source_url=${SOURCE_URL:-$expected_source_url}
[[ "$source_url" == "$expected_source_url" ]] \
  || die "SOURCE_URL must identify the exact fork commit: ${expected_source_url}"
docker_image=patcharp/openobserve:${release_tag#v}

jq -n \
  --arg distribution 'PCPLAB OpenObserve OSS fork' \
  --arg release_channel "$release_channel" \
  --arg company_release "$release_tag" \
  --arg fork_sha "$fork_sha" \
  --arg upstream_repository 'https://github.com/openobserve/openobserve' \
  --arg upstream_source_version "$source_version" \
  --arg upstream_base_sha "$base_sha" \
  --arg upstream_base_type "$base_type" \
  --arg upstream_security_patch_shas "$security_patch_shas" \
  --arg upstream_security_advisories "$security_advisories" \
  --arg build_timestamp "$build_timestamp" \
  --arg docker_image "$docker_image" \
  --arg license 'AGPL-3.0' \
  --arg source "$source_url" \
  '{
    distribution: $distribution,
    release_channel: $release_channel,
    company_release: $company_release,
    fork_sha: $fork_sha,
    upstream_repository: $upstream_repository,
    upstream_source_version: $upstream_source_version,
    upstream_base_sha: $upstream_base_sha,
    upstream_base_type: $upstream_base_type,
    upstream_security_patch_shas: $upstream_security_patch_shas,
    upstream_security_advisories: $upstream_security_advisories,
    build_timestamp: $build_timestamp,
    docker_image: $docker_image,
    license: $license,
    source: $source
  }'
