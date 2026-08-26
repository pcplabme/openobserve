## Issue

Refs #

## Summary

<!-- What changes, and why? -->

## Validation

<!-- List commands/checks actually run and their results. -->

## Fork impact

Does this PR modify upstream-owned files?

- [ ] No
- [ ] Yes

If yes, why could this not be implemented behind an extension boundary?

Modified upstream-owned files:

<!-- Paste the relevant paths from scripts/fork-delta.sh. -->

Expected upstream conflict risk:

- [ ] Low
- [ ] Medium
- [ ] High

Fork-delta result or impact:

<!-- Run: scripts/fork-delta.sh -->

## Review checklist

- [ ] Tests cover the changed behavior, or the reason tests are not needed is stated.
- [ ] Security and privacy considerations are described (or `None`).
- [ ] Database/schema migration impact is described (or `None`).
- [ ] Documentation and operational impact is described (or `None`).
- [ ] New dependencies and their licenses were reviewed (or no dependencies were added).

For `sync/upstream-*` or `sync/security-*` PRs:

- [ ] Upstream source version, exact SHA, and base type are recorded.
- [ ] Migration and dependency diffs received explicit review.
- [ ] Upstream compatibility checks passed.
- [ ] PCPLAB contract checks passed, or an approved emergency exception is documented.
- [ ] Rollback and post-sync/reconciliation notes are included.
