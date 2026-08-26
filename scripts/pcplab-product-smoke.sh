#!/usr/bin/env bash

set -euo pipefail

script_name=$(basename "$0")
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

: "${ZO_ROOT_USER_EMAIL:?ZO_ROOT_USER_EMAIL must be set}"
: "${ZO_ROOT_USER_PASSWORD:?ZO_ROOT_USER_PASSWORD must be set}"

base_url=${ZO_BASE_URL:-http://localhost:5080/}
base_url=${base_url%/}
org=${PCPLAB_SMOKE_ORG:-default}
stream=${PCPLAB_SMOKE_STREAM:-pcplab_contract_smoke}
auth=$(printf '%s' "${ZO_ROOT_USER_EMAIL}:${ZO_ROOT_USER_PASSWORD}" | base64 | tr -d '\r\n')
fixture_dir="${repo_root}/tests/test-data/test-assist-ci/seed"
tmp_root=${TMPDIR:-/tmp}
work_dir=$(mktemp -d "${tmp_root}/pcplab-product-smoke.XXXXXX")
dashboard_id=

cleanup() {
  if [[ -n "$dashboard_id" ]]; then
    curl --silent --show-error --fail-with-body \
      -H "Authorization: Basic ${auth}" \
      -X DELETE "${base_url}/api/${org}/dashboards/${dashboard_id}" >/dev/null 2>&1 || true
  fi
  case "$work_dir" in
    "${tmp_root}"/pcplab-product-smoke.*) rm -rf -- "$work_dir" ;;
    *) printf '%s: refusing to remove unexpected path: %s\n' "$script_name" "$work_dir" >&2 ;;
  esac
}
trap cleanup EXIT

for command in curl jq base64 tr; do
  command -v "$command" >/dev/null 2>&1 || {
    printf '%s: required command is unavailable: %s\n' "$script_name" "$command" >&2
    exit 2
  }
done

for fixture in logs_seed.json metrics_seed.json traces_seed.json; do
  [[ -f "${fixture_dir}/${fixture}" ]] || {
    printf '%s: required fixture is missing: %s\n' "$script_name" "$fixture" >&2
    exit 2
  }
done

request() {
  local method=$1
  local url=$2
  local data_file=${3:-}
  local args=(
    --silent --show-error --fail-with-body
    --connect-timeout 10 --max-time 30
    -X "$method"
    -H "Authorization: Basic ${auth}"
  )
  if [[ -n "$data_file" ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "@${data_file}")
  fi
  curl "${args[@]}" "$url"
}

printf '%s: waiting for startup at %s\n' "$script_name" "$base_url"
healthy=false
for attempt in $(seq 1 90); do
  if curl --silent --show-error --fail "${base_url}/healthz" >"${work_dir}/health.json" 2>/dev/null; then
    healthy=true
    break
  fi
  sleep 1
done
if [[ "$healthy" != true ]]; then
  printf '%s: product startup failure: /healthz did not become ready\n' "$script_name" >&2
  exit 10
fi
jq -e '.status == "ok"' "${work_dir}/health.json" >/dev/null
request GET "${base_url}/config" | jq -e . >/dev/null

now_seconds=$(date +%s)
start_seconds=$((now_seconds - 60))
end_seconds=$((now_seconds + 300))
start_microseconds=$((start_seconds * 1000000))
end_microseconds=$((end_seconds * 1000000))
start_nanoseconds="${start_seconds}000000000"
end_nanoseconds="${now_seconds}000000000"

jq --arg start "$start_nanoseconds" --arg end "$end_nanoseconds" '
  (.. | objects | select(has("startTimeUnixNano")) | .startTimeUnixNano) = $start |
  (.. | objects | select(has("timeUnixNano")) | .timeUnixNano) = $end
' "${fixture_dir}/metrics_seed.json" >"${work_dir}/metrics.json"
jq --arg start "$start_nanoseconds" --arg end "$end_nanoseconds" '
  (.. | objects | select(has("startTimeUnixNano")) | .startTimeUnixNano) = $start |
  (.. | objects | select(has("endTimeUnixNano")) | .endTimeUnixNano) = $end
' "${fixture_dir}/traces_seed.json" >"${work_dir}/traces.json"

printf '%s: validating log ingest and query\n' "$script_name"
request POST "${base_url}/api/${org}/${stream}/_json" "${fixture_dir}/logs_seed.json" \
  | jq -e '(.code // 200) == 200' >/dev/null
jq -n --arg stream "$stream" --argjson start "$start_microseconds" --argjson end "$end_microseconds" \
  '{query:{sql:("SELECT * FROM \"" + $stream + "\""),start_time:$start,end_time:$end,from:0,size:10}}' \
  >"${work_dir}/log-search.json"
log_found=false
for attempt in $(seq 1 30); do
  if request POST "${base_url}/api/${org}/_search" "${work_dir}/log-search.json" \
    >"${work_dir}/log-result.json" 2>"${work_dir}/log-error.txt" && \
    jq -e '.hits | length >= 1' "${work_dir}/log-result.json" >/dev/null; then
    log_found=true
    break
  fi
  sleep 1
done
[[ "$log_found" == true ]] || {
  printf '%s: product regression: ingested logs were not queryable\n' "$script_name" >&2
  sed 's/^/  /' "${work_dir}/log-error.txt" >&2 || true
  exit 20
}

printf '%s: validating metric ingest and PromQL query\n' "$script_name"
request POST "${base_url}/api/${org}/v1/metrics" "${work_dir}/metrics.json" | jq -e . >/dev/null
metric_found=false
for attempt in $(seq 1 30); do
  if curl --silent --show-error --fail-with-body \
    -H "Authorization: Basic ${auth}" --get \
    --data-urlencode 'query=http_requests_total' \
    --data-urlencode "time=${now_seconds}" \
    "${base_url}/api/${org}/prometheus/api/v1/query" \
    >"${work_dir}/metric-result.json" 2>"${work_dir}/metric-error.txt" && \
    jq -e '.status == "success" and (.data.result | length >= 1)' "${work_dir}/metric-result.json" >/dev/null; then
    metric_found=true
    break
  fi
  sleep 1
done
[[ "$metric_found" == true ]] || {
  printf '%s: product regression: ingested metrics were not queryable\n' "$script_name" >&2
  sed 's/^/  /' "${work_dir}/metric-error.txt" >&2 || true
  exit 21
}

printf '%s: validating trace ingest and query\n' "$script_name"
request POST "${base_url}/api/${org}/v1/traces" "${work_dir}/traces.json" | jq -e . >/dev/null
jq -n --argjson start "$start_microseconds" --argjson end "$end_microseconds" \
  '{query:{sql:"SELECT * FROM default",start_time:$start,end_time:$end,from:0,size:10}}' \
  >"${work_dir}/trace-search.json"
trace_found=false
for attempt in $(seq 1 30); do
  if request POST "${base_url}/api/${org}/_search?type=traces" "${work_dir}/trace-search.json" \
    >"${work_dir}/trace-result.json" 2>"${work_dir}/trace-error.txt" && \
    jq -e '.hits | length >= 1' "${work_dir}/trace-result.json" >/dev/null; then
    trace_found=true
    break
  fi
  sleep 1
done
[[ "$trace_found" == true ]] || {
  printf '%s: product regression: ingested traces were not queryable\n' "$script_name" >&2
  sed 's/^/  /' "${work_dir}/trace-error.txt" >&2 || true
  exit 22
}

printf '%s: validating dashboard API lifecycle\n' "$script_name"
jq -n '{version:8,title:"PCPLAB contract smoke",description:"PCPLAB CI product contract",folder_id:"default",tabs:[]}' \
  >"${work_dir}/dashboard.json"
request POST "${base_url}/api/${org}/dashboards" "${work_dir}/dashboard.json" \
  >"${work_dir}/dashboard-result.json"
dashboard_id=$(jq -er '.v8.dashboardId' "${work_dir}/dashboard-result.json")
request GET "${base_url}/api/${org}/dashboards/${dashboard_id}" \
  | jq -e '.v8.title == "PCPLAB contract smoke"' >/dev/null

printf '%s: PASS (startup, logs, metrics, traces, dashboard/API)\n' "$script_name"
