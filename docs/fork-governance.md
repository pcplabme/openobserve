# Patcharp OpenObserve fork governance

This document is the maintainer runbook for the long-lived Patcharp fork of
OpenObserve OSS. It governs upstream intake, release provenance, fork-delta
control, and the security patch lane. It does not define or implement OIDC,
RBAC, audit trail, service ownership, internal integration APIs, or OpenObserve
Enterprise equivalents.

The canonical upstream is `openobserve/openobserve:main`; the releasable fork
integration branch is `patcharp/openobserve:main`. Automation may report and
prepare work. A maintainer decides what reaches `main`.

## Repository analysis at foundation baseline

The analysis below was performed on 2026-08-26 at fork baseline
`2c17c07a11387536a77e6fb0762a0d1da97fe4f3`. The source tree, not this summary,
remains authoritative after future syncs.

- The root Rust package is also a workspace with more than 30 crates under
  `src/`. HTTP/gRPC/API concerns are split under `src/api/`; domain behavior is
  concentrated in `src/core/`; persistence and SeaORM code live primarily in
  `src/infra/` and `src/db/`; configuration is a dedicated `src/config/` crate.
- The Vue 3/TypeScript frontend is in `web/`. Routes are composed in
  `web/src/router/index.ts` and `web/src/router/routes.ts` from shared routes and
  an OSS/edition route provider. Navigation is separately assembled in
  `web/src/layouts/MainLayout.vue`.
- Authentication is not a single replaceable provider. Token validation and
  helpers live in `src/api/common/src/auth/`, request extraction and edition
  switches live in `src/core/src/auth.rs`, and users/org membership cross
  `src/core/src/users.rs`, `src/infra/src/table/users.rs`, and
  `src/infra/src/table/org_users.rs`. HTTP middleware and route registration are
  in `src/api/http/`.
- Authorization has a narrower seam: `src/core/src/authz.rs` funnels permission
  decisions and currently has enterprise and permissive OSS implementations.
  Route metadata is carried by `AuthExtractor` in `src/core/src/auth.rs`.
- Configuration uses `dotenv_config::EnvConfig` structures in
  `src/config/src/config.rs`, loaded into a reloadable global `ArcSwap<Config>`.
  Build version, commit, and timestamp are produced by `src/config/build.rs` and
  exposed through `config::VERSION`, `COMMIT_HASH`, and `BUILD_DATE`.
- Application schema migration is startup-managed by `src/migration/mod.rs`.
  Ordered SeaORM migrations live in `src/infra/src/table/migration/`, while
  `DB_SCHEMA_VERSION` lives in `src/config/src/config.rs`. The existing
  `db-schema-version-check.yml` enforces a schema-version bump when a migration
  is added. Database migration review must cover both locations and all
  supported engines.
- Rust unit tests are generally colocated with crates, with additional root and
  crate integration tests. API tests live under `tests/api-testing`, database
  validation under `tests/db-testing`, and the frontend has Vitest unit tests
  plus Playwright/Cypress-style suites. Existing workflows already separate
  unit, database, API, and UI/E2E concerns.
- Release tags trigger `.github/workflows/release.yml`. The current build
  metadata uses the nearest Git tag plus the fork commit and build date; it does
  not yet expose all Patcharp/upstream provenance in-product. Issue #10 owns the
  remaining About/Legal/Source surface and release-workflow integration.
- `src/enterprise/o2_dex`, `o2_openfga`, `o2_enterprise`, and `o2_ratelimit` are
  dependency-resolution stubs for private crates. The `src/audit` crate is
  compiled only with the `enterprise` feature and depends on private audit
  types. The OSS fork must create independent contracts and implementations;
  these stubs are not reusable Enterprise source.
- A 500-commit path-frequency sample identified `web/src/` as the largest churn
  area, followed by `src/core`, `src/api`, `src/infra`, and `src/search`.
  Repeated hotspots include `src/config/src/config.rs`, `Cargo.toml`,
  `Cargo.lock`, `web/package*.json`,
  `src/api/http/src/handler/http/router/mod.rs`,
  `src/infra/src/table/migration/mod.rs`, frontend locale files, and
  `MainLayout.vue`. Persistent fork edits in these files carry elevated sync
  risk.

The initial upstream source manifest declares `0.93.0`. The baseline SHA above
was verified as an upstream `main` commit. No `v0.93.0` upstream tag was present
when this foundation was created, so the base type is `main-development`, not
`release-tag`.

## Branch and history policy

```text
main
├── feature/*
├── fix/*
├── chore/*
├── sync/upstream-YYYY-MM-DD
└── sync/security-<CVE-or-topic>
```

`main` is always the releasable integration branch.

- Changes reach `main` through pull requests. Do not push or merge upstream
  directly into `main`.
- Never rebase shared `main`, force-push it, or delete it.
- Normal upstream intake occurs on `sync/upstream-YYYY-MM-DD`, approximately
  every two weeks. Failed attempts are aborted or discarded without changing
  `main`.
- Merge upstream with explicit ancestry. The sync branch contains a real merge
  commit from `upstream/main`; the sync PR itself must use GitHub's **Create a
  merge commit** method. Squashing or rebasing that PR would discard the
  ancestry the policy is intended to preserve.
- Feature, fix, and chore PRs may use the repository's normal merge strategy.
- Critical/high security work may use `sync/security-<CVE-or-topic>` at any
  time, but still requires a PR and traceable review.

## Machine-readable upstream adoption record

`.fork/upstream.env` records the last upstream snapshot the fork has adopted:

```text
UPSTREAM_REPOSITORY=https://github.com/openobserve/openobserve.git
UPSTREAM_SOURCE_VERSION=0.93.0
UPSTREAM_BASE_SHA=<exact fully integrated upstream commit>
UPSTREAM_BASE_TYPE=release-tag|main-development|security-cherry-pick
UPSTREAM_SECURITY_PATCH_SHAS=<comma-separated targeted upstream fixes, if any>
```

The file is input data, not executable shell. Scripts parse it without
`source`. Update it in the same sync/security PR that changes the adopted base.
`UPSTREAM_BASE_SHA` remains the last fully integrated upstream snapshot so
fork-delta comparisons stay meaningful. A targeted security release sets base
type to `security-cherry-pick` and records fix SHA(s) separately.

## Normal upstream synchronization

Configure the canonical remote once:

```bash
git remote add upstream https://github.com/openobserve/openobserve.git
git remote get-url upstream
```

If `upstream` already exists but is wrong, stop and inspect it before using
`git remote set-url`. For each sync:

```bash
git fetch --prune upstream origin

git switch main
git pull --ff-only origin main

sync_branch="sync/upstream-$(date -u +%F)"
git switch -c "$sync_branch"

upstream_sha=$(git rev-parse upstream/main)
git merge --no-ff --no-commit upstream/main
```

The `--no-commit` pause is intentional. Before committing:

1. Resolve conflicts according to the rules below.
2. Review migrations and schema version changes.
3. Review dependency manifests, lockfiles, licenses, toolchains, build images,
   and actions.
4. Confirm the root `Cargo.toml` source version and whether the upstream SHA is
   actually a release tag.
5. Update `.fork/upstream.env` with the exact `upstream_sha`, source version,
   correct base type, and reconciled security patch list.

Then create the upstream merge commit and push the review branch:

```bash
# Non-conflicting merge results are already staged. Add only files you inspected.
git status --short
git add .fork/upstream.env
# git add each resolved conflict path explicitly
git diff --cached --check
git commit

scripts/fork-delta.sh --details
bash scripts/upstream-drift.sh upstream/main

git push -u origin "$sync_branch"
gh pr create --base main --head "$sync_branch" --title "chore(sync): adopt upstream $(date -u +%F)"
```

The commit message must identify the exact upstream SHA. Do not edit the
upstream merge commit after review has started; add follow-up commits so review
remains auditable.

### Conflict handling

- Resolve only on the sync branch. Never resolve by taking all of `ours` or all
  of `theirs` across the repository.
- Establish intended behavior from the current fork tests, linked Patcharp
  issues, and the upstream commits touching the conflict. Preserve upstream
  behavior unless a documented company contract requires otherwise.
- Treat auth/user paths, migrations, `Cargo.toml`/lockfiles, API routers,
  configuration, release automation, frontend route composition, and
  `MainLayout.vue` as high-risk even when Git reports a clean merge.
- For every persistent upstream-owned modification, ask whether the company
  behavior can move behind a narrow interface. Record unavoidable decisions in
  the PR Fork impact section.
- Record files that actually conflicted in the sync PR. The drift tool reports
  current overlap hotspots; PR history is the lightweight recurring-conflict
  log until repeated evidence warrants a dedicated dataset.

The sync author owns each resolution and its evidence. A maintainer familiar
with the affected subsystem reviews high-risk resolutions; migration changes
receive explicit database review and security-sensitive paths receive explicit
security impact review. This defines review responsibility without imposing a
fixed approval count that a small team cannot reliably satisfy.

If the attempt is not viable:

```bash
git merge --abort
git switch main
git branch -D "$sync_branch"
```

Delete a pushed failed sync branch only after confirming no useful review work
depends on it. None of these operations rewrite or change `main`.

### Database migration review

For every upstream sync, reviewers must inspect:

```bash
git diff ORIG_HEAD..HEAD -- src/infra/src/table/migration src/config/src/config.rs src/migration
```

Check migration ordering and registration, `up`/`down` behavior, data rewrite
cost and locking, SQLite/PostgreSQL compatibility, backups, mixed-version
deployment behavior, and the `DB_SCHEMA_VERSION` change. Run the existing DB
schema check and database validation workflow. Never promise rollback by binary
revert when an irreversible schema/data migration has run; test restoration or
a forward repair before release.

### Dependency and supply-chain review

Inspect `Cargo.toml`, `Cargo.lock`, crate manifests, `deny.toml`,
`web/package.json`, `web/package-lock.json`, build images, toolchains, GitHub
Actions, and any newly fetched scripts. Confirm licenses and provenance for new
dependencies, examine security advisories, and explain unusual Git revisions or
unpinned branches. Reuse existing cargo-deny, license, build, and frontend checks
instead of duplicating them.

## Validation gates

Two concepts remain separate:

- **Upstream compatibility checks** prove the adopted OpenObserve source still
  builds and passes the relevant upstream Rust, frontend, DB, API, and E2E
  checks.
- **Patcharp contract checks** prove company-owned behavior and extension
  contracts still work. Issue #3 owns the initial executable regression suite
  and its required aggregate status check.

Minimum policy by branch:

| PR head | Required before merge |
| --- | --- |
| `feature/*`, `fix/*`, `chore/*` | Existing affected upstream checks; Patcharp contract tests for any company behavior changed; fork-delta report when the PR changes architecture or upstream-owned files. |
| `sync/upstream-*` | Full applicable upstream compatibility matrix, DB migration validation, dependency/license review, fork-delta report, drift report, and mandatory Patcharp contract aggregate gate from #3. |
| `sync/security-*` | Targeted upstream checks plus Patcharp contract gate. Any test skipped under emergency authority must be named, risk-assessed, approved in the PR, and run immediately after deployment. |

Do not clone every expensive upstream workflow into a Patcharp workflow. Issue
#3 should add one stable company-owned entry point and aggregate check, initially
reusing `tests/api-testing` and `tests/db-testing` where they protect company
contracts. New company features add tests to that suite as part of their own
PRs.

## Fork-delta control

Run the report on committed work:

```bash
scripts/fork-delta.sh
scripts/fork-delta.sh --details
```

The report compares the current commit with `.fork/upstream.env` and shows the
fork SHA, exact upstream base, company-only files, modified upstream-owned
files, changed upstream-owned lines, company-owned text lines, and the
persistent conflict surface. Binary files are counted but excluded from LOC.

The primary budget is **modified upstream-owned files**, not LOC. The default
expectation for a company feature is no new persistent upstream-file delta
beyond a narrow composition hook. Any increase requires the PR to name the
files, explain why a boundary was insufficient, assess churn/conflict risk, and
state how the patch could later be retired. A decrease is always called out.
High-churn files from the repository analysis require Medium or High risk even
for small line counts. The team may set numeric thresholds after several syncs;
inventing a hard cap without history would encourage gaming rather than better
boundaries.

## Security patch lane

Monitor authoritative OpenObserve
[security advisories](https://github.com/openobserve/openobserve/security/advisories),
[releases](https://github.com/openobserve/openobserve/releases), and
[upstream commits](https://github.com/openobserve/openobserve/commits/main), plus
Rust/npm advisory results already surfaced by repository automation. The
maintainer on security intake owns triage through a documented affected or
unaffected decision and assigns the patch/release owner. Do not rely on
commit-message keywords as the only security feed.

Critical remotely exploitable issues affecting a deployed configuration and
High issues with plausible exposure receive immediate impact analysis. Medium,
Low, or non-applicable findings may wait for the normal sync only when the
decision and evidence are recorded.

```text
Critical/High upstream issue
        |
        v
impact analysis
   |             |
unaffected      affected
   |          |          |
record      isolated   dependent
decision      patch      changes
              |            |
          cherry-pick  emergency sync
```

### Isolated upstream fix

```bash
git fetch --prune upstream origin
git switch main
git pull --ff-only origin main
git switch -c sync/security-<CVE-or-topic>
git cherry-pick -x <upstream-fix-sha>
```

The `-x` trailer preserves upstream provenance. Update
`UPSTREAM_BASE_TYPE=security-cherry-pick` and append the exact fix SHA to
`UPSTREAM_SECURITY_PATCH_SHAS`; do not move `UPSTREAM_BASE_SHA` unless a full
upstream snapshot was merged. Open a PR containing the advisory, affected
configuration/versions, upstream fix SHA, fork commits, tests, rollout,
rollback, and reconciliation plan.

### Dependent fix / emergency sync

When the fix depends on broader upstream work, use
`sync/security-<CVE-or-topic>` but perform the normal `--no-ff --no-commit`
upstream merge. Review the expanded change surface explicitly. The branch name
records urgency; the adopted base type remains `main-development` (or a real
`release-tag`) because the full snapshot was integrated.

### Post-cherry-pick reconciliation

At the next normal sync, verify whether `upstream/main` contains every recorded
security fix. Merge normally, resolve equivalent-patch conflicts by preserving
the reviewed final behavior, and run the same security regression cases. Remove
only reconciled SHAs from `UPSTREAM_SECURITY_PATCH_SHAS`; reset the base type to
the actual adopted snapshot type. Link the scheduled sync PR back to the
security PR and advisory so the chain remains:

```text
upstream advisory -> upstream fix SHA -> fork PR -> fork release SHA -> deployed version
```

## Rollback

Never reset or force-push shared `main`.

1. Stop rollout or route traffic back to the last known-good immutable release.
2. Open a `fix/*` rollback PR that reverts the sync/security PR's merge commit
   with `git revert -m 1 <merge-sha>` (or reverts the isolated cherry-pick).
3. Re-run required gates and publish a new Patcharp revision. Do not move an
   existing release tag.
4. If migrations ran, follow the reviewed migration recovery plan: restore a
   verified backup, execute a tested down migration, or ship a forward repair.
5. Record affected deployments and reconcile `.fork/upstream.env` with the
   content actually restored. A later retry uses a new sync branch and PR.

## Release and provenance policy

Fork releases derive from the adopted upstream source version:

```text
v<UPSTREAM_SOURCE_VERSION>-patcharp.<REVISION>
```

Examples are `v0.93.0-patcharp.1`, `v0.93.0-patcharp.2`, and
`v0.93.0-patcharp.3`. Release candidates use valid SemVer prerelease identifiers
such as `v0.93.0-patcharp.3.rc.1`. When the adopted source manifest changes from
`0.93.0` to `0.94.0`, reset the Patcharp revision to `.1`.

The tag is a label, not the provenance authority. Every artifact/release record
must preserve:

```text
Distribution
Company release
Fork SHA
Upstream source version
Upstream exact base SHA
Upstream base type
Upstream security patch SHA(s), when applicable
Build timestamp
License
Corresponding Source location
```

Create and validate an annotated tag locally only after the sync/feature PR is
merged and the release commit passes required checks. Do not push the immutable
tag until the version and provenance manifest validate successfully:

```bash
git switch main
git pull --ff-only origin main

release=v0.93.0-patcharp.1
git tag -a "$release" -m "Patcharp OpenObserve $release"

metadata_file=$(mktemp)
trap 'rm -f "$metadata_file"' EXIT
scripts/fork-release-metadata.sh "$release" > "$metadata_file" &&
  jq -e . "$metadata_file" >/dev/null &&
  git push origin "$release"
```

The local manifest is pre-push validation evidence, not the release artifact.
The build job must regenerate it using the artifact's actual build timestamp and
retain it beside checksums and source for the same immutable tag. Do not retag a
failed release; increment the Patcharp revision. Issue #10 still
must wire this manifest into release artifacts and the product's prominent
About/Legal/Source mechanism, define historical source retention/access, and
complete legal review. Preserve `LICENSE` and all upstream notices. Do not copy,
reverse engineer, or imply use of proprietary OpenObserve Enterprise code.

## Required GitHub ruleset for `main`

No branch protection or repository ruleset was active when inspected on
2026-08-26. Create an active branch ruleset targeting exactly
`refs/heads/main` with:

- restrict deletions;
- block non-fast-forward updates (force pushes);
- require a pull request before merging, with zero required approving reviews
  initially for the small maintainer team;
- require conversation resolution;
- require status checks and require the branch to be up to date before merge;
- do **not** require linear history, because validated upstream sync PRs retain
  an upstream merge commit;
- allow merge commits in repository merge settings; sync PRs must use them;
- do not grant a routine bypass that permits direct pushes to `main`.

The exact intended REST payload is below. Apply it only after #3 exists and all
listed contexts have reported at least once on `main`:

```json
{
  "name": "Protect Patcharp main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "allowed_merge_methods": ["merge", "squash", "rebase"],
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_approving_review_count": 0,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "do_not_enforce_on_create": false,
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "unit_tests_summary" },
          { "context": "db_schema_version_check" },
          { "context": "db_tests_summary" },
          { "context": "api_tests_summary" },
          { "context": "patcharp_contract_tests" }
        ]
      }
    }
  ]
}
```

Save that JSON as a temporary file outside the repository and apply it with an
administrator token:

```bash
gh api --method POST repos/patcharp/openobserve/rulesets --input /path/to/ruleset.json
```

The field names and behavior follow GitHub's
[repository rulesets REST API](https://docs.github.com/en/rest/repos/rules) and
[available rules documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets).

After #3 lands a stable aggregate job, require these non-conditional aggregate
checks (confirm their emitted GitHub check names before saving the ruleset):

```text
unit_tests_summary
db_schema_version_check
db_tests_summary
api_tests_summary
patcharp_contract_tests   # pending #3
```

If existing aggregate checks are conditional or do not report for docs-only
changes, fix their aggregation before making them required; a permanently
pending check is not a governance control. GitHub cannot express different
required checks solely from PR head prefixes in one `main` ruleset, so the
`patcharp_contract_tests` workflow must enforce the stricter sync/security
matrix internally.

Repository-admin configuration remains manual/pending: this PR cannot safely
activate the ruleset before #3 supplies the company contract check and before
the actual check names have passed on `main` at least once.

## Maintainer checklists

### Sync PR

- [ ] Exact upstream SHA/source version/base type recorded.
- [ ] Real upstream merge commit retained; PR merge method will also be merge commit.
- [ ] Conflicts and persistent fork edits explained.
- [ ] DB migrations/schema version reviewed and recovery plan recorded.
- [ ] Dependencies, actions, build images, licenses, and advisories reviewed.
- [ ] Upstream compatibility and Patcharp contract gates passed.
- [ ] `scripts/fork-delta.sh --details` attached.
- [ ] Release, rollout, rollback, and security reconciliation notes complete.

### Release

- [ ] Tag matches `v<upstream>-patcharp.<revision>[.rc.<revision>]` and is immutable.
- [ ] Source version matches root `Cargo.toml`; upstream tag claim was verified.
- [ ] Provenance JSON generated during the actual artifact build and retained with checksums.
- [ ] Exact corresponding source for the fork SHA is retained and accessible.
- [ ] Upstream notices and AGPL-3.0 license remain present.
- [ ] New dependency licenses and source obligations were reviewed.
- [ ] Deployment record links release tag, fork SHA, upstream base/fix SHAs, and environment.

## Known dependencies and follow-up work

- Issue #3: implement the executable Patcharp contract suite and stable required
  aggregate check. Until then, the policy is documented but the company gate is
  not enforceable by GitHub.
- Issue #10: add in-product fork attribution/source access and integrate the
  provenance manifest into release artifacts and historical source retention.
- Repository administration: activate the documented `main` ruleset after the
  required checks exist and their names are verified.
- Automatic sync PR creation is intentionally deferred. The drift workflow
  reports only; maintainers choose when and what to integrate.
