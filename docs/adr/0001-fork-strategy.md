# ADR 0001: Long-lived fork strategy and extension boundaries

- Status: Accepted
- Date: 2026-08-26
- Decision owners: Patcharp OpenObserve maintainers
- Related issues: #1, #2, #3, #4, #10, #11

## Context

Patcharp maintains an internal-use fork of OpenObserve OSS under AGPL-3.0. The
fork will add company requirements while continuing to receive upstream bug,
security, dependency, schema, backend, frontend, and CI changes. Upstream moves
quickly, and the recurring cost of a fork is dominated by understanding and
resolving persistent local edits during each upstream integration.

At foundation baseline `2c17c07a11387536a77e6fb0762a0d1da97fe4f3`, the root
manifest declares OpenObserve source version `0.93.0`. That SHA is from
upstream `main`; it is not an upstream `v0.93.0` release tag. Exact source SHAs
therefore matter more than the version label.

The repository is a Rust workspace with API, core, configuration, persistence,
and other crates under `src/`, plus a Vue frontend under `web/`. Its existing
edition boundaries are not a general extension system: Rust Enterprise paths
are feature-gated and several `src/enterprise/*` crates are dependency stubs for
private code; the existing audit crate also depends on private types. Patcharp
must implement OSS-compatible requirements independently without copying or
deriving proprietary Enterprise implementations.

Future identity, authorization, auditing, ownership, integration, metadata, and
UI work must not scatter company conditionals across high-churn core files. This
ADR establishes where that future work may attach; it does not implement those
features.

## Decision drivers

- Preserve a reviewable ancestry relationship with `openobserve/openobserve`.
- Make failed upstream syncs discardable without risking `main`.
- Keep company code discoverable and persistent edits to upstream files small.
- Preserve upstream behavior and AGPL notices.
- Support emergency security intake without abandoning normal reconciliation.
- Give CI and releases exact, reproducible upstream/fork provenance.
- Fit the repository's actual crate, router, config, and migration structure.

## Decision

### Upstream integration and history

The fork adopts upstream approximately every two weeks through
`sync/upstream-YYYY-MM-DD`. The sync branch merges `upstream/main` with an
explicit merge commit, resolves and validates there, then reaches `main` by a PR
that also uses a merge commit. Shared `main` is never rebased or force-pushed.
Security fixes use `sync/security-<CVE-or-topic>` and either `cherry-pick -x` an
isolated upstream fix or perform an emergency upstream merge when dependencies
require it. The operational procedure is in `docs/fork-governance.md`.

### Versioning and provenance

Release tags use `v<UPSTREAM_SOURCE_VERSION>-patcharp.<REVISION>`. Release
candidates append `.rc.<REVISION>`. The Patcharp revision resets to `.1` when
the adopted upstream source version changes.

A tag alone is never authoritative. `.fork/upstream.env` records the adopted
upstream source version, exact fully integrated SHA, base type, and targeted
security fix SHAs. Release artifacts additionally record company release, fork
SHA, build timestamp, license, and Corresponding Source location.

### Extension-boundary policy

The dependency direction is:

```text
upstream request/domain path
          |
          v
small neutral trait, event, registry, or router hook
          ^
          |
Patcharp implementation selected at the composition root
```

Contracts live at the narrowest existing upstream boundary whose domain types
they need. Patcharp implementations depend on those contracts; upstream core
must not depend on concrete Patcharp behavior. Prefer explicit dependency
injection. When process-wide selection is unavoidable, initialize a typed
registry once during bootstrap and make absence behavior explicit and tested.

Company configuration uses a `PATCHARP_` environment prefix and is parsed in
company-owned code. Do not expand the already high-churn upstream `Config`
structure unless upstream code genuinely consumes the setting. Company database
objects and migrations use a `patcharp_` namespace and a separate company
schema-version record; a single startup composition hook runs them after the
upstream migrator. This avoids inserting company migrations into upstream's
ordered `src/infra/src/table/migration/mod.rs` list.

A core modification is permitted only to establish or invoke a narrow boundary
that cannot be composed outside the core. The PR must list each upstream-owned
file, explain the rejected non-core option, describe default behavior when the
company provider is absent, add contract tests, and assess upstream churn.
Hooks must remain useful without a `patcharp` string or company-specific policy
inside upstream business logic wherever practical.

### Company-owned namespace

Use these locations for future implementation work:

```text
.fork/                         adopted-upstream machine metadata
src/patcharp/                  company-owned Rust crate/subtree
web/src/patcharp/              company frontend routes, components, stores, services
tests/patcharp/                company contract and integration tests
docs/                          governance and architecture records
scripts/fork-*                 fork maintenance/release tooling
```

The first backend feature should create `src/patcharp/` as a dedicated workspace
crate with capability modules rather than add a `patcharp` module inside many
upstream crates. If dependency direction later requires multiple company crates,
keep them below the same subtree and add explicit workspace members. Do not put
company code under `src/enterprise/` or `web/src/enterprise/`; those paths
represent upstream edition boundaries and could imply copied Enterprise code.

Only create these feature directories as features are implemented. Empty
scaffolding would add maintenance surface without establishing a tested
contract.

### Proposed boundary map

The file column lists the expected persistent upstream touch surface, not work
authorized by this ADR. Exact files must be revalidated against the then-current
tree before implementation.

| Capability | Existing path and required hook | Contract shape | Company location | Expected persistent upstream-owned edits |
| --- | --- | --- | --- | --- |
| Authentication provider | Authentication currently crosses `src/api/common/src/auth/`, `src/core/src/auth.rs`, HTTP middleware/router code, and user tables. Add provider selection at the request-authentication boundary; keep user persistence behind existing core/infra services. Extension callback/login routes are contributed as a router, not inserted handler-by-handler. | Async `AuthenticationProvider` accepting normalized credentials/request context and returning a typed `Principal` or typed auth error; optional session/login router contribution. Default provider preserves current OSS Basic/token behavior. | `src/patcharp/src/authn/` | One provider/registry module near `src/api/common/src/auth/`, the central auth middleware/extractor call site, composition-root wiring, and one router nest if browser callbacks are later needed. |
| Authorization evaluator | `src/core/src/authz.rs` already funnels `check_permissions` and object listing. Replace edition-specific selection with a provider boundary while retaining `AuthExtractor` route metadata. | Async `AuthorizationProvider::{is_allowed,list_objects}` over a stable subject/action/resource/context model. Provider errors deny protected actions unless an explicitly public/default OSS path applies. | `src/patcharp/src/authz/` | Primarily `src/core/src/authz.rs`, its crate manifest, and composition-root initialization. Avoid edits to individual handlers. |
| Audit event emitter | `src/audit` is Enterprise-only and private-type-coupled, so do not reuse its event model. Add an OSS-neutral event contract near service/middleware boundaries. HTTP middleware may supply transport context; domain services supply semantic action/outcome. | Async non-blocking `AuditEventSink::emit(AuditEvent)` with actor, organization, action, resource, outcome, request/trace IDs, timestamp, and redacted metadata. Delivery failure policy and backpressure are explicit. | `src/patcharp/src/audit/` | A neutral contract module, one HTTP middleware hook, composition-root/flush lifecycle hooks, and only those domain service hooks needed for events that cannot be inferred safely from HTTP. |
| Company integration API | HTTP APIs are centrally composed in `src/api/http/src/handler/http/router/mod.rs`. Mount one company router built entirely in the Patcharp crate; use existing core services rather than duplicate handlers. | A versioned Axum router/service facade with company DTOs mapped to upstream domain services. Authentication and authorization use the provider contracts above. | `src/patcharp/src/api/` | Root/API crate dependency plus one `nest`/merge call in central router composition. No scattered company routes in upstream handler modules. |
| Service/team ownership adapter | Upstream service-stream data exists in `src/core`/`src/infra`, but company ownership is a separate source of truth. Keep lookup and caching out of core unless an upstream UI/API explicitly needs ownership enrichment. | Async `OwnershipProvider::resolve(ServiceRef) -> Ownership`, with stable service identity, team reference, provenance, freshness, and not-found/error distinction. | `src/patcharp/src/ownership/` | Initially none beyond the company API. If core/UI consumes ownership, one enrichment service hook and one frontend extension contribution rather than columns/conditions throughout service-stream code. |
| Build/version metadata | Existing `src/config/build.rs` provides tag, commit, and build date; status/config responses are in `src/api/management/src/request/status/mod.rs`. Generate Patcharp metadata independently, then merge it into the existing status/About response. | Immutable `ForkBuildMetadata` containing distribution, company release, fork SHA, upstream version/SHA/base type/security patches, build timestamp, license, and source location. | `.fork/upstream.env`, `scripts/fork-release-metadata.sh`, later `src/patcharp/src/build_metadata/` | Company crate build script/manifest, one API status response integration, and later one frontend About/Legal contribution under #10. Avoid teaching general config about release policy. |
| Company frontend routes/components | Routes already merge route providers in `web/src/router/index.ts`/`routes.ts`; navigation is separately assembled in high-churn `MainLayout.vue`. Add one Patcharp UI manifest consumed by both route and navigation composition. | A typed `PatcharpUiExtension` exposing route records, navigation entries, optional config/bootstrap data, and feature guards. Components lazy-load. | `web/src/patcharp/{routes,components,services,stores}/` | One route-provider import/merge and one navigation contribution hook. Do not append company cases throughout `MainLayout.vue` or shared route tables. |

Authentication and authorization remain separate contracts. Audit observes their
outcomes but must not become the authorization mechanism. Ownership adapters do
not implicitly grant access. The company API does not bypass the normal authn,
authz, validation, and error contracts.

### Database and migration boundary

Upstream startup currently checks `DB_SCHEMA_VERSION`, acquires the database
initialization lock, runs `infra::table::migrate()`, and then records the
upstream version. A future Patcharp schema should:

1. run through one composition call after successful upstream migration;
2. use the existing DDL client and distributed-lock facility but a distinct
   lock/version key;
3. keep company migration files and tests under `src/patcharp/`;
4. support every metadata database the fork claims to support;
5. make backup, downgrade/forward-repair, and mixed-version behavior explicit.

This design requires a narrow startup hook but avoids recurring edits to the
upstream migration registry. It must be implemented and tested only when the
first company-owned table is justified.

### Fork-delta budget and review

`scripts/fork-delta.sh` compares the fork to the exact adopted upstream base.
The primary indicator is the count and identity of modified upstream-owned
files. Company-only files, changed upstream-owned LOC, company LOC, binary
files, and current SHAs are supporting evidence.

The default budget is no increase in persistent upstream-owned files except for
the smallest tested composition hook. There is no initial numeric LOC cap: LOC
can be gamed and a one-line edit in a high-churn router can cost more than a
large isolated company module. Each PR records the delta and risk. Each sync
looks for removable patches when upstream gains an equivalent public extension.
Repeated conflict paths are recorded in sync PRs; `scripts/upstream-drift.sh`
also reports overlap between current fork edits and new upstream changes.

### CI and regression strategy

Existing upstream-compatible checks remain authoritative for OSS behavior.
Patcharp adds a separate company contract suite with a stable aggregate status
under #3. It runs on PRs to `main`, becomes mandatory for
`sync/upstream-*`/`sync/security-*`, and grows with each company feature. The
suite reuses existing API/DB/UI harnesses when useful but does not duplicate
upstream coverage merely to claim ownership.

### Security patch lane

Critical/High upstream issues receive immediate impact analysis. Isolated fixes
are cherry-picked with provenance on `sync/security-*`; dependent fixes use an
emergency upstream merge. Both paths use PR review, regression testing or an
explicitly approved and time-bounded emergency exception, immutable release
metadata, rollback planning, and reconciliation during the next normal sync.

## Alternatives considered

### Continuously mirror upstream

Rejected. Automatic continuous integration would shorten drift windows but
would also combine upstream volatility with company release decisions and make
regression ownership unclear. Scheduled drift reporting provides visibility
without changing branches; maintainers choose an integration window.

### Infrequent large upstream merges

Rejected. Fewer sync events reduce routine overhead but compound conflicts,
schema changes, dependency review, and behavior changes into high-risk projects.
Biweekly review keeps the delta understandable while allowing cadence to flex.

### Rebase fork history onto upstream

Rejected for shared branches. Rebase creates clean-looking history by rewriting
company commits, disrupts collaborators and deployed SHA traceability, and makes
failed coordination hazardous. Merge commits preserve both lineages.

### Modify core directly without extension boundaries

Rejected. Scattered conditions are fast for the first feature but maximize
recurring conflicts, complicate testing, and obscure which behavior belongs to
the company. A small stable hook plus isolated implementation makes the cost
visible and replaceable.

### Maintain a permanently patched copy of each subsystem

Rejected. Duplicating authentication, user management, routing, migration, or
frontend subsystems would silently miss upstream fixes and invite incompatible
data/API behavior. Patcharp wraps or contributes at seams and keeps upstream as
the implementation of shared behavior.

### Reuse or recreate OpenObserve Enterprise implementations

Rejected. The OSS repository contains feature gates and dependency stubs, not
authority to copy proprietary implementations. Patcharp requirements are
designed independently against OSS contracts and remain subject to AGPL and
company legal review.

### Independent company versions unrelated to upstream

Rejected. A standalone `1.0`, date-only version, or build number hides the
source line from operators. The upstream-derived tag conveys compatibility;
exact fork/upstream SHAs and base type provide reproducibility.

### Put company code into existing Enterprise directories

Rejected. Those directories encode upstream edition semantics and private-crate
stubs. Reusing the namespace would confuse provenance, increase collision risk,
and weaken the independent-implementation rule.

## Consequences

### Benefits

- Every upstream intake is isolated, reviewable, abortable, and traceable.
- Exact source provenance survives moving version labels and development-line
  bases.
- Company behavior is discoverable by path and test ownership.
- Most future feature changes should land in company-only files, with a small
  and measurable core conflict surface.
- Security patches can move faster without creating silent permanent divergence.
- Upstream compatibility and company contracts fail independently and are
  easier to diagnose.

### Operational costs and trade-offs

- Maintainers perform regular drift review, merge conflict analysis, migration
  and dependency review, and release bookkeeping.
- Stable extension contracts require design work before feature implementation.
- Some upstream files must still carry narrow hooks and will require attention
  on every sync.
- Merge history is non-linear, and sync PRs must use a specific merge method to
  retain ancestry.
- A separate company migration/version path and contract test suite add ongoing
  ownership.
- The GitHub ruleset, full company regression gate, release artifact wiring, and
  in-product AGPL/source display remain dependencies of issues #3/#10 and
  repository administration; documentation alone does not enforce them.

## Compliance note

This is an engineering architecture decision, not legal advice. Preserve the
AGPL-3.0 license and upstream copyright notices, attribute modifications, make
the exact Corresponding Source available through the mechanism completed under
#10, review licenses for new dependencies, and keep deployed source/release
records immutable. No decision here permits use of proprietary OpenObserve
Enterprise source.
