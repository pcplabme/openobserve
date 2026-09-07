# PCPLAB OpenObserve — Multi-Agent Engineering Governance Workflow

## 1. Purpose

This document defines the operating model for developing and maintaining the PCPLAB OpenObserve fork.

Repository:

- Fork: `https://github.com/pcplabme/openobserve`
- Upstream: `https://github.com/openobserve/openobserve`

The workflow separates:

1. **Product/Requirement authority**
2. **Execution orchestration**
3. **Architecture/research specialists**
4. **Implementation workers**
5. **Independent verification**

The primary objective is not maximum coding speed. It is requirement completeness, technical correctness, controlled fork divergence, reproducible releases, auditable execution, and reliable upstream maintenance.

---

# 2. Organizational Model

```text
User / Product Owner
        │
        ▼
Independent PM
(ChatGPT / GPT-5.6 Sol)
        │
        │ requirements / priorities / acceptance
        ▼
Codex Orchestrator
(Execution Manager)
        │
        ├──────────────┬──────────────┬──────────────┐
        ▼              ▼              ▼              ▼
     Codex          Claude          Agy          OpenCode
 Implementation   Architecture    Research /     Minimax M3
 / QA Worker      / Deep Review   Cross-check    Fast Worker
```

## Authority hierarchy

```text
Product Owner
    ↓
Independent PM
    ↓
Codex Orchestrator
    ↓
Workers
```

Workers do **not** redefine product scope.

Codex Orchestrator does **not** silently redefine acceptance criteria.

Independent PM does **not** directly micromanage implementation unless a design or requirement needs correction.

---

# 3. Role Definitions

## 3.1 Product Owner

Owns business intent, priorities, final product direction, deployment constraints, risk tolerance, and acceptance of major trade-offs.

The Product Owner may provide high-level requests such as:

> Add AI-assisted RCA to OpenObserve.

The Product Owner is not expected to fully specify technical decomposition.

## 3.2 Independent PM — ChatGPT / GPT-5.6 Sol

Owns **requirements governance**.

Responsibilities:

- convert product intent into implementable requirements,
- research product/technical alternatives,
- create or refine GitHub Issues,
- define milestone scope,
- define dependencies,
- define acceptance criteria,
- identify missing requirements,
- challenge incomplete implementation,
- audit roadmap drift,
- perform independent architecture/product review,
- verify that Codex did not prematurely close work,
- recommend follow-up issues when scope gaps are discovered.

Canonical authority for:

```text
WHAT must be delivered
WHY it matters
WHEN it belongs in the roadmap
WHAT counts as complete
```

An issue is not complete merely because code exists.

Completion requires acceptance criteria satisfied, required tests passing, documentation updated, security implications addressed, operational implications addressed, fork-maintenance impact considered, and no unresolved required checklist items.

## 3.3 Codex Orchestrator

Codex is the **execution manager**.

Owns:

```text
HOW work is decomposed
WHO performs each task
HOW changes are integrated
HOW implementation progress is verified
```

Codex must:

- read the relevant GitHub issue in full before execution,
- inspect dependency issues,
- inspect current repository state,
- create an execution plan,
- decompose large issues into explicit sub-tasks,
- assign workers based on strengths,
- coordinate parallel work where safe,
- review worker output,
- integrate changes,
- run required validation,
- maintain issue checklist state,
- keep the branch/PR aligned with acceptance criteria,
- stop and escalate when a requirement/design decision is ambiguous.

Codex is forbidden from declaring work complete while required issue items remain unfinished.

## 3.4 Claude — Architecture / Deep Review Specialist

Use Claude primarily for:

- system architecture,
- complex Rust design,
- authorization/security architecture,
- distributed-system reasoning,
- database/schema migration review,
- query engine changes,
- concurrency/lifecycle analysis,
- security design review,
- high-risk code review,
- architecture ADR proposals.

Claude should usually produce design analysis, trade-offs, interfaces/contracts, risk analysis, and review findings.

Claude may implement complex code when useful, but Codex remains execution owner.

## 3.5 Agy — Research / Alternative Design / Cross-Check

Use Agy for:

- broad technical research,
- alternative architectural approaches,
- upstream behavior comparison,
- dependency/library evaluation,
- performance research,
- UX/product comparisons,
- independent second opinion,
- adversarial design review.

Agy output is research evidence, not automatic implementation direction.

## 3.6 OpenCode / Minimax M3 — Fast Implementation Worker

Use OpenCode/Minimax M3 for:

- bounded implementation tasks,
- repetitive code changes,
- tests,
- API wiring,
- frontend components,
- refactoring inside clearly defined boundaries,
- documentation updates,
- fixtures,
- straightforward CI changes.

Best task shape:

```text
clear input
clear files/boundary
clear expected output
clear tests
```

Avoid assigning M3 ambiguous architecture work without a prior design.

## 3.7 Codex Worker

Codex may also act as a worker when repository-wide understanding, implementation plus verification, tooling integration, GitHub/CI work, or repair of another worker's output is required.

The Orchestrator must still distinguish planning, implementation, and review roles.

Do not self-approve work without validation.

---

# 4. Core Workflow

## Stage 0 — Requirement Intake

Input: Product Owner request.

Independent PM:

1. Clarifies objective.
2. Researches relevant upstream/OpenObserve behavior.
3. Identifies product and technical constraints.
4. Defines issue(s).
5. Defines milestone.
6. Defines dependencies.
7. Defines acceptance criteria.
8. Defines non-goals where useful.

Output:

```text
GitHub Issue(s)
Milestone assignment
Roadmap update
```

No implementation begins before the requirement is sufficiently actionable.

## Stage 1 — Codex Intake

Codex must read issue body, milestone, linked dependencies, relevant ADRs, `AGENTS.md`, repository governance documentation, and current branch/repository status.

Codex produces an **Execution Plan**:

```text
Issue:
Goal:

Dependencies:
Blocking dependencies:

Repository areas affected:

Execution tasks:
T1
T2
T3
...

Worker assignment:
T1 → Claude
T2 → Codex
T3 → OpenCode
...

Validation plan:

Risks / open decisions:

Definition of Done mapping:
AC1 → tasks/tests
AC2 → tasks/tests
...
```

Codex must explicitly map work to issue acceptance criteria.

## Stage 2 — Architecture Gate

Mandatory for changes affecting authentication, authorization, audit, data model, migrations, query engine, scheduler/QoS, distributed execution, AI runtime, MCP/tool execution, anomaly engine, RCA, sensitive data, action runner, federation, or fork extension boundaries.

Recommended flow:

```text
Codex
  ↓
Claude architecture analysis
  ↓
Agy alternative / cross-check if high risk
  ↓
Codex synthesis
  ↓
ADR / design note where required
```

Implementation must not proceed with unresolved architectural contradictions.

## Stage 3 — Task Decomposition

Large issues must be decomposed into bounded units.

Example:

```text
Issue #29 RCA Orchestrator

T1 Evidence contract review
T2 RCA job model
T3 LLM provider abstraction
T4 MCP tool policy
T5 Orchestrator state machine
T6 structured output schema
T7 API endpoints
T8 frontend integration
T9 evaluation fixtures
T10 security tests
```

Each task needs owner, input, output, files/boundary, acceptance condition, and tests.

## Stage 4 — Parallel Execution

Parallel execution is allowed only when boundaries are clean.

Safe:

```text
Claude      → architecture / review
Codex       → backend API
OpenCode    → frontend component
Agy         → algorithm/library research
```

Unsafe: multiple workers independently modifying the same core subsystem.

Codex owns conflict prevention.

## Stage 5 — Worker Handoff Protocol

Every worker must report:

```text
Task:
Status: complete / blocked / partial

Files changed:

Implementation summary:

Tests executed:
- command
- result

Requirements satisfied:

Known limitations:

Unfinished work:

Risks / follow-ups:
```

A worker saying "done" has no authority to close the task unless Codex verifies it.

## Stage 6 — Codex Integration Review

Codex verifies worker output against task specification, issue requirements, fork architecture, upstream compatibility, security requirements, and tests.

Reject/return work if tests were not actually run, implementation is incomplete, acceptance criteria are ignored, unrelated refactors were introduced, upstream-owned files were modified unnecessarily, security controls were omitted, or code duplicates a subsystem instead of using extension boundaries.

## Stage 7 — Independent Verification

Before issue closure, Codex performs a full issue audit.

Required **Completion Matrix**:

| Acceptance criterion | Evidence | Status |
|---|---|---|
| AC1 | test/API/commit | PASS |
| AC2 | test/docs | PASS |
| AC3 | unresolved | FAIL |

If any required criterion is FAIL:

```text
Issue status = NOT COMPLETE
```

Codex must also inspect issue checklist, TODO/FIXME introduced by the work, skipped tests, deferred required scope, security findings, migration concerns, and docs.

## Stage 8 — PR

Each implementation should normally land through a PR.

PR must contain issue reference, scope, architecture summary, files/areas changed, fork impact, tests, security implications, migration impact, operational impact, known limitations, and acceptance criteria mapping.

## Stage 9 — Independent PM Audit

For major milestones or high-risk issues, Independent PM reviews issue vs delivered scope, architecture consistency, acceptance criteria, roadmap implications, missing follow-up requirements, and premature closure risk.

Independent PM audit has exactly two outcomes:

```text
PASS
FAILED
```

Definitions:

- `PASS` — all required acceptance criteria and required review findings for the audited scope are satisfied. The work may proceed to merge/closure/release as applicable.
- `FAILED` — one or more required acceptance criteria or review findings remain unsatisfied. The work must return to execution, then be submitted for a fresh audit.

There is no `PASS WITH CHANGES`, `PASS WITH FOLLOW-UP`, `PARTIAL PASS`, or equivalent intermediate state. If a change is required before the audited scope can proceed, the result is `FAILED`.

Non-blocking recommendations may still be recorded separately, but they do not alter a `PASS` result and must not be used to hide required work.

## Independent PM Binary Audit Policy

Audit/review is a gate, not a progress label.

```text
required work remains? ── yes ──> FAILED
          │
          no
          │
          ▼
         PASS
```

A `FAILED` result must list the concrete findings that need correction. After corrections are made, Codex requests a new audit. Previous failed findings are re-verified together with any affected acceptance criteria.

A `PASS` result means the audited scope has no unresolved required findings. Optional ideas or future enhancements must be clearly marked non-blocking and tracked separately if useful.

---

# Stage 10 — Release Gate

A milestone release requires all required milestone issues complete, CI/regression passing, release provenance valid, no unresolved blocking security issue, Docker image produced, immutable image version published, release notes prepared, and upstream/fork SHA recorded.

Canonical artifact:

```text
Git tag:
v<UPSTREAM>-pcplab.<N>

Docker:
patcharp/openobserve:<UPSTREAM>-pcplab.<N>
```

---

# 5. Agent Selection Matrix

| Work Type | Primary | Secondary |
|---|---|---|
| Requirement / roadmap | Independent PM | Codex |
| Architecture | Claude | Codex / Agy |
| Deep Rust reasoning | Claude | Codex |
| Standard backend implementation | Codex | OpenCode |
| Frontend implementation | OpenCode | Codex |
| CI / release automation | Codex | OpenCode |
| Research / alternatives | Agy | Claude |
| Security design | Claude | Codex |
| Security implementation | Codex | Claude review |
| Tests / fixtures | OpenCode | Codex |
| Performance research | Agy | Claude |
| Performance implementation | Codex | Claude |
| ML/anomaly research | Agy | Claude |
| AI/RCA architecture | Claude | Agy |
| AI/RCA implementation | Codex | OpenCode |
| Final execution verification | Codex | Independent PM audit |

---

# 6. Anti-Premature-Completion Policy

Codex must never treat these statements as evidence of completion:

```text
"implemented core functionality"
"main flow works"
"remaining work is minor"
"follow-up issue can handle it"
"tests look okay"
```

unless the original issue explicitly allows the remaining work to be deferred.

Required issue items cannot be silently moved to new issues merely to close the current one.

If scope changes, Independent PM / Product Owner approval is required.

---

# 7. Task State Model

```text
BACKLOG
READY
IN_DESIGN
IN_PROGRESS
IN_REVIEW
BLOCKED
READY_FOR_PM_AUDIT
DONE
```

Recommended transition:

```text
BACKLOG
  ↓
READY
  ↓
IN_DESIGN (if needed)
  ↓
IN_PROGRESS
  ↓
IN_REVIEW
  ↓
READY_FOR_PM_AUDIT
  ↓
DONE
```

`DONE` requires acceptance criteria satisfaction.

---

# 8. Decision Escalation

Codex must stop and escalate when issue requirements conflict, architectural choice materially affects roadmap, security model changes, license implications arise, public API/backward compatibility must break, upstream merge strategy must change, milestone scope needs to move, or acceptance criteria cannot be satisfied as written.

Escalation format:

```text
Decision required:

Context:

Options:
A
B
C

Trade-offs:

Codex recommendation:

Impact if delayed:
```

Independent PM/Product Owner decides.

---

# 9. Fork-Specific Engineering Rules

1. Minimize edits to upstream-owned files.
2. Prefer PCPLAB modules/adapters/interfaces.
3. Preserve upstream behavior where possible.
4. Never copy proprietary Enterprise implementation.
5. Public AGPL contracts/scaffolding may be reused where legally/technically appropriate.
6. Every custom feature needs regression coverage.
7. Upstream mergeability is a design constraint.
8. Fork delta is an engineering metric.
9. Release provenance must identify exact upstream and fork SHAs.

---

# 10. Upstream Sync Workflow

Normal cadence: every ~2 weeks.

```text
upstream/main
    ↓
sync/upstream-YYYY-MM-DD
    ↓
conflict analysis
    ↓
tests + PCPLAB regressions
    ↓
PR
    ↓
main
```

Security patches may use:

```text
sync/security-YYYY-MM-DD-<topic>
```

No direct upstream merge to `main`.

---

# 11. Definition of Done

An issue is DONE only when all required acceptance criteria pass, all required checklist items are complete, implementation is merged, tests pass, regression tests are added where needed, security review is completed where needed, docs are updated, operational configuration is documented, migration impact is handled, fork-delta impact is reviewed, and no known blocking defects remain.

For high-risk issues:

```text
Independent PM audit recommended before closure.
```

---

# 12. Canonical Working Pattern

```text
Independent PM
    ↓ requirement
GitHub Issue
    ↓
Codex
    ↓ execution plan
Architecture specialist if required
    ↓
Workers
    ↓
Codex integration/review
    ↓
CI / regression
    ↓
PR
    ↓
Independent PM audit
    ↓
merge / release
```

This is the canonical PCPLAB OpenObserve engineering workflow.
