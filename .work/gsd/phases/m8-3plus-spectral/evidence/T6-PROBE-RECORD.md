# M8-3+ T6 three-stamp probe record

## Leg 1 (static, this lane)

| id | check | verdict | detail |
|---|---|---|---|
| T6-STATIC-ORDER | filmRecordDidChange schedules before rendering | PASS | schedule@381 render@412 |
| T6-STATIC-SCOPE | PipeCoordinator diff is the single T6 hunk (0 post-commit) | PASS | 1 hunk(s) vs HEAD |
| T6-STATIC-SIBLINGS | sibling call sites keep render-before-write | PASS | 7 sibling sites unmoved |

## Leg 2 (runtime, orchestrator approval round)

Recipe: cold pair (fresh DerivedData or new pair) → open
image → enable film → capture S1 (commit log line) / S2
(tc build completion — bake log) / S3 (.lra mtime).

Verdict slot: S3 ≈ S1+2s = HOLD / S3 ≈ S2+2s = FALSIFIED.

Status: PENDING (no live app in this lane).

## m-6① undo leg (zero code)

Recipe: outside the cold build window, undo a rotation →
the viewport restores immediately (the R8 36b condition
reversed). Status: PENDING (orchestrator walkthrough).
