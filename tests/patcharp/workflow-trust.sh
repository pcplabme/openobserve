#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'workflow-trust-test: %s\n' "$*" >&2
  exit 1
}

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflows_dir="${repo_root}/.github/workflows"

[[ -d "$workflows_dir" ]] || fail "missing ${workflows_dir}"

tmp_root=${TMPDIR:-/tmp}
tmp_dir=$(mktemp -d "${tmp_root}/patcharp-workflow-trust.XXXXXX")

cleanup() {
  case "$tmp_dir" in
    "${tmp_root}"/patcharp-workflow-trust.*)
      rm -rf -- "$tmp_dir"
      ;;
    *)
      printf 'workflow-trust-test: refusing to remove unexpected path: %s\n' "$tmp_dir" >&2
      ;;
  esac
}
trap cleanup EXIT

shopt -s nullglob
owned_workflows=("$workflows_dir"/patcharp-*.yml "$workflows_dir"/upstream-drift.yml)
shopt -u nullglob

if [[ ${#owned_workflows[@]} -ne 6 ]]; then
  fail "expected exactly six owned workflows, found ${#owned_workflows[@]}"
fi

issues_log="${tmp_dir}/issues.log"
: >"$issues_log"

record() {
  printf '%s\n' "$*" >>"$issues_log"
}

leading_indent() {
  local line=$1
  local n=${#line}
  local i=0
  while (( i < n )); do
    if [[ "${line:i:1}" != " " ]]; then
      break
    fi
    i=$((i + 1))
  done
  printf '%d' "$i"
}

# check_run_block_safety: emit a record per unsafe line found in `run:` blocks.
# An "event-expression" interpolation is any ${{ }} in a `run:` script that
# touches the GitHub event payload. matrix/inputs/secrets/needs/steps/vars
# references are evaluated to controlled values and are permitted; the
# canonical script-injection vector is github.event.* plus the heads/refs.
unsafe_regex='github\.(event\.|head_ref|ref|ref_name|repository|repository_owner|sha|actor|triggering_actor)'

is_unsafe_run_line() {
  local text=$1
  [[ "$text" =~ $unsafe_regex ]]
}

check_run_block_safety() {
  local file=$1

  local in_block=0
  local block_indent=-1
  local line_no=0
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    if [[ -z "$line" ]]; then
      continue
    fi
    local indent
    indent=$(leading_indent "$line")
    local stripped=${line#"${line%%[![:space:]]*}"}

    # Leaving a block: same or lower indent line that isn't blank.
    if (( in_block )) && (( indent <= block_indent )); then
      in_block=0
      block_indent=-1
    fi

    # Inspect current line for `run:` markers.
    if [[ "$stripped" =~ ^run:[[:space:]]*([|>]?)([+-]?)([[:space:]]*)(.*)$ ]]; then
      local style="${BASH_REMATCH[1]}"
      local rest="${BASH_REMATCH[4]}"
      if [[ -n "$style" ]]; then
        # Block scalar: open a script block.
        in_block=1
        block_indent=$indent
        if is_unsafe_run_line "$rest"; then
          record "${file}:${line_no}: unsafe event-expression interpolation in run block opening: ${rest}"
        fi
      else
        # Scalar run: check this whole line.
        if is_unsafe_run_line "$rest"; then
          record "${file}:${line_no}: unsafe event-expression interpolation in scalar run: ${rest}"
        fi
        in_block=0
      fi
      continue
    fi

    # Inside an open run block, detect event-expression interpolation.
    if (( in_block )); then
      if is_unsafe_run_line "$stripped"; then
        record "${file}:${line_no}: unsafe event-expression interpolation in run block: ${stripped}"
      fi
    fi
  done <"$file"
}

is_pr_lane() {
  local file=$1
  awk '
    /^on:[[:space:]]*$/ { in_on = 1; next }
    in_on && /^[^ ]/ { in_on = 0 }
    in_on && /^[[:space:]]*(pull_request|pull_request_target|merge_group|workflow_call):[[:space:]]*$/ {
      found = 1
      exit
    }
    END { exit !found }
  ' "$file"
}

for wf in "${owned_workflows[@]}"; do
  base=$(basename "$wf")

  # Top-level permissions: required for every owned workflow.
  if ! grep -qE '^permissions:[[:space:]]*(#.*)?$' "$wf"; then
    record "${base}: missing top-level permissions declaration"
  fi

  # Forbidden triggers: pull_request_target, issue_comment, repository_dispatch.
  if grep -qE '^[[:space:]]*pull_request_target:[[:space:]]*' "$wf"; then
    record "${base}: forbidden trigger pull_request_target is present"
  fi
  if grep -qE '^[[:space:]]*issue_comment:[[:space:]]*' "$wf"; then
    record "${base}: forbidden trigger issue_comment is present"
  fi
  if grep -qE '^[[:space:]]*repository_dispatch:[[:space:]]*' "$wf"; then
    record "${base}: forbidden trigger repository_dispatch is present"
  fi

  # Secrets are allowed outside the PR lane; inside it, any secrets.* reference
  # is rejected to prevent token exposure through attacker-controlled PRs.
  if is_pr_lane "$wf"; then
    if grep -qE 'secrets\.[A-Za-z0-9_-]+' "$wf"; then
      record "${base}: secrets.* interpolation is not allowed in Patcharp-owned PR-lane workflows"
    fi
  fi

  # Unsafe ${{ interpolation inside run: script blocks. Applies to every
  # owned workflow regardless of lane because ${{ }} in `run:` is the
  # canonical script-injection vector.
  check_run_block_safety "$wf"
done

if [[ -s "$issues_log" ]]; then
  cat "$issues_log" >&2
  fail "$(grep -c . "$issues_log") workflow trust violation(s)"
fi

printf 'workflow-trust-test: PASS (%d workflow(s) audited)\n' "${#owned_workflows[@]}"
