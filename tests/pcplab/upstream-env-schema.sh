#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'upstream-env-schema-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
metadata_file="${repo_root}/.fork/upstream.env"
cargo_toml="${repo_root}/Cargo.toml"

[[ -f "$metadata_file" ]] || fail "metadata file missing: ${metadata_file}"
[[ -f "$cargo_toml" ]] || fail "Cargo.toml missing: ${cargo_toml}"

required_keys=(
  UPSTREAM_REPOSITORY
  UPSTREAM_SOURCE_VERSION
  UPSTREAM_BASE_SHA
  UPSTREAM_BASE_TYPE
)

# Security patch/advisory keys are required to be present (the metadata
# contract forbids omitting them) but may be empty for ordinary upstream bases.
required_key_allowed_empty=(
  UPSTREAM_SECURITY_PATCH_SHAS
  UPSTREAM_SECURITY_ADVISORIES
)

declare -A seen=()
declare -A allowed_empty=()
for key in "${required_key_allowed_empty[@]}"; do
  allowed_empty[$key]=1
done

while IFS='=' read -r key value; do
  [[ -n "$key" ]] || continue
  case "$key" in
    '#'*|'') continue ;;
  esac
  seen[$key]=${value-}
done <"$metadata_file"

for key in "${required_keys[@]}"; do
  if [[ -z "${seen[$key]+set}" ]]; then
    fail "required key missing in ${metadata_file}: ${key}"
  fi
  if [[ -z "${seen[$key]}" ]]; then
    fail "required key empty in ${metadata_file}: ${key}"
  fi
done

# Verify every optional-empty key is at least declared; value may be empty.
for key in "${required_key_allowed_empty[@]}"; do
  if [[ -z "${seen[$key]+set}" ]]; then
    fail "required key missing in ${metadata_file}: ${key}"
  fi
done

base_sha=${seen[UPSTREAM_BASE_SHA]}
if ! [[ "$base_sha" =~ ^[0-9a-f]{40}$ ]]; then
  fail "UPSTREAM_BASE_SHA must be a 40-hex commit SHA; got: ${base_sha}"
fi

base_type=${seen[UPSTREAM_BASE_TYPE]}
case "$base_type" in
  release-tag|main-development|security-cherry-pick) ;;
  *)
    fail "UPSTREAM_BASE_TYPE must be release-tag|main-development|security-cherry-pick; got: ${base_type}"
    ;;
esac

source_version=${seen[UPSTREAM_SOURCE_VERSION]}
if ! [[ "$source_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  fail "UPSTREAM_SOURCE_VERSION must be SemVer; got: ${source_version}"
fi

cargo_version=$(awk -F'"' '
  BEGIN { in_package = 0; depth = 0 }
  /^\[package\]/ { in_package = 1; next }
  in_package && /^\[/ { in_package = 0 }
  in_package && /^version[[:space:]]*=/ { sub(/^version[[:space:]]*=[[:space:]]*"/, ""); sub(/".*/, ""); print; exit }
' "$cargo_toml")

if [[ -z "$cargo_version" ]]; then
  fail "could not extract root package version from ${cargo_toml}"
fi
if [[ "$cargo_version" != "$source_version" ]]; then
  fail "UPSTREAM_SOURCE_VERSION (${source_version}) does not match Cargo.toml version (${cargo_version})"
fi

# Validate the recorded SHA resolves in the local repository.
if ! git -C "$repo_root" cat-file -e "${base_sha}^{commit}" 2>/dev/null; then
  fail "UPSTREAM_BASE_SHA ${base_sha} does not resolve to a local commit"
fi

# Validate the recorded repository URL is well-formed and https+git.
repository=${seen[UPSTREAM_REPOSITORY]}
if ! [[ "$repository" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(\.git)?$ ]]; then
  fail "UPSTREAM_REPOSITORY must be a https GitHub URL; got: ${repository}"
fi

# UPSTREAM_SECURITY_PATCH_SHAS accepts empty list or comma-separated hex SHAs.
validate_security_metadata() {
  local candidate_base_type=$1
  local security_shas=$2
  local security_advisories=$3

  if [[ -n "$security_shas" ]]; then
    local entry
    for entry in ${security_shas//,/ }; do
      if ! [[ "$entry" =~ ^[0-9a-f]{7,40}$ ]]; then
        fail "UPSTREAM_SECURITY_PATCH_SHAS entry must be a hex SHA; got: ${entry}"
      fi
    done
  fi

  if [[ -n "$security_advisories" ]]; then
    local advisory
    for advisory in ${security_advisories//,/ }; do
      if ! [[ "$advisory" =~ ^CVE-[0-9]{4}-[0-9]{4,}$|^GHSA-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}$|^EMBARGOED$ ]]; then
        fail "UPSTREAM_SECURITY_ADVISORIES entry must be CVE, GHSA, or EMBARGOED; got: ${advisory}"
      fi
    done
  fi

  if [[ "$candidate_base_type" == security-cherry-pick ]]; then
    [[ -n "$security_shas" ]] \
      || fail 'security-cherry-pick requires UPSTREAM_SECURITY_PATCH_SHAS'
    [[ -n "$security_advisories" ]] \
      || fail 'security-cherry-pick requires UPSTREAM_SECURITY_ADVISORIES'
  fi
}

security_shas=${seen[UPSTREAM_SECURITY_PATCH_SHAS]}
security_advisories=${seen[UPSTREAM_SECURITY_ADVISORIES]}
validate_security_metadata "$base_type" "$security_shas" "$security_advisories"

# Exercise fail-closed branches independently of the current adoption record.
for invalid_advisory in CVE-2026-123 GHSA-bad EMBARGOED-123 arbitrary; do
  if (validate_security_metadata main-development '' "$invalid_advisory") >/dev/null 2>&1; then
    fail "invalid security advisory was accepted: ${invalid_advisory}"
  fi
done
for valid_advisory in CVE-2026-1234 GHSA-abcd-1234-efgh EMBARGOED; do
  (validate_security_metadata security-cherry-pick deadbee "$valid_advisory") >/dev/null 2>&1 \
    || fail "valid security metadata was rejected: ${valid_advisory}"
done
if (validate_security_metadata security-cherry-pick '' CVE-2026-1234) >/dev/null 2>&1; then
  fail 'security-cherry-pick accepted an empty security patch list'
fi
if (validate_security_metadata security-cherry-pick deadbee '') >/dev/null 2>&1; then
  fail 'security-cherry-pick accepted an empty advisory list'
fi

printf 'upstream-env-schema-test: PASS\n'
