# PCPLAB CI, regression, security, and release gates

PCPLAB owns six workflow entrypoints. They use public GitHub-hosted runners,
do not require AI/provider secrets, and keep required check names under company
control.

| Workflow | Purpose | Stable aggregate |
| --- | --- | --- |
| `pcplab-pr.yml` | changed-file routing, Rust/frontend checks, DB/API guards, fork delta | `pcplab_pr_gate` |
| `pcplab-contract.yml` | outer company gate: static contracts, security, and conditional full regression | `pcplab_contract_tests` |
| `pcplab-regression.yml` | reusable full SQLite, PostgreSQL, and product/API regression | `pcplab_regression_tests` |
| `pcplab-security.yml` | reusable Rust, JavaScript, license, and workflow supply-chain checks | `pcplab_security_gate` |
| `pcplab-release.yml` | immutable multi-architecture Docker Hub release | internal release gates |
| `upstream-drift.yml` | read-only upstream visibility | advisory only |

Only `pcplab_pr_gate` and `pcplab_contract_tests` are proposed as permanent
`main` ruleset requirements. Activate the ruleset only after both names have
reported successfully on `main`. The contract workflow calls the security
workflow on every PR and calls the full regression workflow for
`sync/upstream-*`, `sync/security-*`, non-PR `main`, merge queue, and manual
runs. Its outer aggregate fails when either called workflow fails, so the two
required checks remain compact without letting a sync PR bypass the stricter
matrix.

## Inherited workflow inventory

The upstream test commands and fixtures remain in the repository even when the
workflow that called them is removed.

### Keep

- `upstream-drift.yml`: PCPLAB governance automation; read-only and never
  auto-merges upstream.

### Replace

- `build-pr-image.yml`, `build-fork-pr-image.yml`: replaced by the tag-only
  PCPLAB release path; untrusted pull requests never publish images.
- `release.yml`: replaced by `pcplab-release.yml` and Docker Hub namespace
  `patcharp/openobserve`.

### Reuse capability

- `api-testing.yml`: reuse `tests/api-testing` and its client/fixtures.
- `audit-checker.yml`: reuse `cargo audit` in `pcplab-security.yml`.
- `cargo-deny.yml`: reuse cargo-deny and license policy.
- `db-schema-version-check.yml`: reuse
  `.github/scripts/check-db-schema-version.sh` in `pcplab-pr.yml`.
- `db-testing.yml`: reuse `tests/db-testing` and PostgreSQL fixtures.
- `js-license-checker.yml`: reuse dependency/license intent in the security
  workflow.
- `mobile-sdk-e2e.yml`: retain its test harness for a future affected-path
  contract.
- `playwright.yml`, `playwright_regression.yml`: retain Playwright tests and
  fixtures for bounded full-regression expansion.
- `pure-api-spec-guard.yml`: reuse its classifier command in `pcplab-pr.yml`.
- `sbom-update.yml`: reuse SBOM capability in `pcplab-release.yml` without its
  upstream PR automation.
- `unit-tests.yml`: reuse cargo, frontend unit, coverage, and cache commands.
- `verify-translations.yml`: retain the validation scripts for affected
  frontend paths.

### Remove

- AI/provider automation: `ai-code-review.yml`, `claude.yml`,
  `claude-auto-implement.yml`, `claude-pr-fix.yml`, `query-agent.yml`,
  `review.yml`, `test-assist-caller.yml`, `e2e-council-caller.yml`.
- Enterprise/internal dispatch: `dispatch-event-enterprise.yml`,
  `ent-e2e-gate.yml`, `docgen-caller.yml`.
- OpenObserve telemetry and organization infrastructure:
  `log-issues-to-o2.yml`, `log-merged-prs.yml`, `o2-metrics-resync.yml`,
  `pr-slack.yml`.
- Upstream process automation: `auto-assign-metadata.yml`,
  `auto-update-features.yml`, `bug-checker.yml`, `feat-design-checker.yml`,
  `merge-queue-auto-requeue.yml`, `ok-to-test.yml`,
  `playwright-auto-rerun.yml`, `pr-title-checker.yml`,
  `release-drafter.yml`, `release-label-applier.yml`, `spam-cleaner.yml`,
  `stale.yml`, `stuck-run-reaper.yml`, `update-translations.yml`.
- Dependency automation not owned by PCPLAB: `npm-update.yml`.

## Local execution

Run the company contract suite from a clean checkout:

```bash
bash scripts/pcplab-contract.sh
```

Run one contract by basename while developing it:

```bash
bash scripts/pcplab-contract.sh fork-release-metadata
```

The strict product contract targets a running OpenObserve process. It verifies
startup/config, log ingest/query, metric ingest/PromQL query, trace
ingest/query, and dashboard create/read/delete with deterministic fixtures:

```bash
export ZO_BASE_URL=http://localhost:5080/
export ZO_ROOT_USER_EMAIL=root@example.com
export ZO_ROOT_USER_PASSWORD='<local-test-password>'
bash scripts/pcplab-product-smoke.sh
```

The script uses only `bash`, `curl`, `jq`, and `base64`. The caller is
responsible for starting OpenObserve with a disposable local configuration.
The workflow uses filesystem storage plus SQLite for API/product tests and a
GitHub service container running `postgres:17.5-alpine3.22` for migration/DB
validation; it needs no NATS, object store, provider credential, custom runner,
or external telemetry endpoint.

The regression workflow intentionally reuses `tests/api-testing`,
`tests/db-testing`, and the existing telemetry fixtures instead of copying
them. Product failures are reported separately from database pytest/JUnit
failures and server-startup failures; server logs and JUnit results are kept as
diagnostic artifacts. Playwright and broader API fixtures remain available for
later affected-path expansion without retaining their inherited workflow
entrypoints.

## Release trust boundary

Confirm access to the `patcharp/openobserve` Docker Hub repository before the first
release. A missing repository and invalid credentials can return
indistinguishable registry errors, so the workflow deliberately fails closed
rather than treating that response as an absent tag.

Create a protected GitHub Environment named `release-dockerhub`. Restrict it to
tags matching `v*-pcplab.*`, require a maintainer reviewer, and store only:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN` — a Docker Hub access token with Read and Write scope, never
  an account password

Enable Docker Hub immutable tags for the `patcharp/openobserve` repository and
cover every full PCPLAB version/RC tag. The workflow also authenticates and
fails closed on registry lookup errors, then repeats the non-existence check
immediately before publication; registry-side immutability is the final defense
against an out-of-band writer or time-of-check/time-of-use race.

`pcplab-release.yml` validates an annotated tag, verifies it is on `main`,
checks the exact tagged SHA for `pcplab_pr_gate` and the outer
`pcplab_contract_tests`, generates provenance, rejects an existing Docker
tag, builds amd64 and arm64 candidates and pushes them without a version tag,
pulls each exact candidate digest, runs the same strict product contract,
generates an SBOM, and scans vulnerabilities against those exact bytes. Only
after both digests pass does the final job validate their platform manifests,
repeat the immutable-tag check, and create the multi-architecture version tag
as its last command. A failed candidate may leave untagged registry content but
never a production version tag. Pull requests cannot reach this path. `latest`
is never published; release candidates never update `stable`.

Before pushing a release tag, wait until `pcplab_pr_gate` and
`pcplab_contract_tests` are green on the intended `main` SHA. The release
workflow checks once and fails closed on an in-progress/missing result; it does
not wait through a long regression run.

## Explicitly deferred regression coverage

The current database lane validates forward migrations against a fresh
PostgreSQL service and the PR lane enforces schema-version changes. Startup
against the previous PCPLAB release schema cannot be implemented until a
first supported PCPLAB release exists. Historical-schema upgrade fixtures and
deeper destructive-migration detection remain required Issue #3 work after that
baseline is published; they are not silently treated as covered by the fresh-DB
tests.

Repository Actions currently permits `local_only` actions, so these workflows'
pinned third-party actions cannot execute yet; no repository ruleset is active.
Keep that restrictive policy until the workflows are merged and a staged canary
is approved. Broadening the Actions allow policy, provisioning the protected
environment and Docker Hub immutability, running a deliberate-failure canary,
performing a dry release, confirming the two emitted outer check names, and only
then activating the ruleset are required operational completion evidence for
Issue #3.
