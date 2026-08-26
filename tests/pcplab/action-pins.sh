#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'action-pins-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflow_dir="${repo_root}/.github/workflows"
[[ -d "$workflow_dir" ]] || fail "missing workflow directory"

files=(
  "$workflow_dir"/pcplab-*.yml
  "$workflow_dir"/upstream-drift.yml
)
[[ ${#files[@]} -eq 6 ]] || fail "expected exactly six owned workflows, found ${#files[@]}"

while IFS= read -r action_file; do
  files+=("$action_file")
done < <(find "${repo_root}/.github/actions" -path '*/pcplab-*/*' -name action.yml -type f 2>/dev/null | sort)

tmp_root=${TMPDIR:-/tmp}
issues=$(mktemp "${tmp_root}/pcplab-action-pins.XXXXXX")
cleanup() {
  case "$issues" in
    "${tmp_root}"/pcplab-action-pins.*) rm -f -- "$issues" ;;
    *) fail "refusing to remove unexpected path: $issues" ;;
  esac
}
trap cleanup EXIT

uses_count=0
declare -A verified_tags=()
for file in "${files[@]}"; do
  while IFS=: read -r line_number line; do
    reference=${line#*uses:}
    reference=${reference#"${reference%%[![:space:]]*}"}
    if [[ "$reference" == ./* || "$reference" == docker://* ]]; then
      continue
    fi
    uses_count=$((uses_count + 1))
    target=${reference%%[[:space:]]#*}
    comment=
    if [[ "$reference" == *'#'* ]]; then
      comment=${reference#*#}
      comment=${comment#"${comment%%[![:space:]]*}"}
    fi
    sha=${target##*@}
    if ! [[ "$target" == *@* && "$sha" =~ ^[0-9a-f]{40}$ ]]; then
      printf '%s:%s: action is not pinned to a 40-hex commit: %s\n' "$file" "$line_number" "$target" >>"$issues"
    elif ! [[ "$comment" =~ v[0-9] ]]; then
      printf '%s:%s: pinned action lacks a version comment: %s\n' "$file" "$line_number" "$reference" >>"$issues"
    elif [[ ${PCPLAB_VERIFY_PINS:-0} == 1 ]]; then
      repository=${target%@*}
      tag=${comment%%[[:space:]]*}
      cache_key="${repository}@${tag}"
      if [[ -n ${verified_tags[$cache_key]:-} ]]; then
        if [[ ${verified_tags[$cache_key]} != "$sha" ]]; then
          printf '%s:%s: repeated tag %s uses inconsistent pinned SHAs\n' \
            "$file" "$line_number" "$cache_key" >>"$issues"
        fi
        continue
      fi
      set +e
      refs=$(git ls-remote --tags "https://github.com/${repository}.git" \
        "refs/tags/${tag}" "refs/tags/${tag}^{}" 2>&1)
      remote_status=$?
      set -e
      if [[ $remote_status -ne 0 ]]; then
        printf '%s:%s: unable to verify %s remotely: %s\n' \
          "$file" "$line_number" "$target" "$refs" >>"$issues"
      elif ! awk -v sha="$sha" '$1 == sha { found=1 } END { exit !found }' <<<"$refs"; then
        printf '%s:%s: comment tag %s does not resolve to pinned SHA %s\n' \
          "$file" "$line_number" "$tag" "$sha" >>"$issues"
      else
        verified_tags[$cache_key]=$sha
      fi
    fi
  done < <(grep -nE '^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*' "$file")
done

if [[ -s "$issues" ]]; then
  cat "$issues" >&2
  fail "action pin violations found"
fi
(( uses_count > 0 )) || fail "no action references were audited"
printf 'action-pins-test: PASS (%d references audited)\n' "$uses_count"
