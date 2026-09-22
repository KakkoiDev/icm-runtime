# Inline-comment calibration log

Ground truth for the value gate: what actually happened to each posted finding.
Append one row per finding after the author/reviewer responds (harvest the raw
threads with `tools/gather-review-feedback <owner>/<repo> <PR#>`, then classify).
Verdicts: `accepted` (author acted or agreed), `rejected(<reason>)` (author pushed
back and was right), `disputed` (pushed back, unresolved), `ignored` (no response).
A finding shape rejected twice becomes a demotion reason in the stage-04 floor or a
scar - that is the point of this file. Precision per PR = accepted / posted.

## `confidence` - record it at decision time, not afterwards

`confidence` is the gate's own stated confidence in the finding, in `[0,1]`, as it
stood **when the decision was made** - before any author response was known.

This is the one column that cannot be reconstructed later. Verdict, severity and
lesson can all be filled in retrospectively from the thread; confidence cannot,
because once the outcome is known the number is contaminated. A row whose
confidence is written after seeing the verdict is worse than a row with no
confidence at all, because it looks usable and is not.

Recording it turns this file from a precision log into a **calibration** log.
Precision answers "how often is the gate right". Calibration answers "when the
gate is wrong, did it know" - which is the property that decides whether a wrong
decision escalates or silently ships.

The emitting side must supply the number: stage 04 produces the judgment, so it
must state a confidence alongside each finding for this column to be fillable.
Until it does, new rows carry `-` and are excluded from calibration scoring in
the same way the pre-existing rows are.

## `set` - fix it when the row is written

`fit` or `eval`. A temperature fitted on rows later used to evaluate it reports a
calibration that does not exist. Assign the set when the row is created, never by
partitioning afterwards, because a partition chosen once the outcomes are visible
is a choice about the result.

## Rows recorded before confidence was tracked

Marked `-` in both new columns. They remain valid as precision data and are
**excluded from any calibration measure**. Do not backfill them.

| date | PR | finding | severity/category | confidence | set | posted as | verdict | lesson |
|------|----|---------|-------------------|-----------:|-----|-----------|---------|--------|
| 2026-07-16 | meetsmore/meetsone#24618 | F1 | LOW/scope | - | - | inline (multi-bullet) | accepted | legit ("required context") but verbose - one engineer-natural sentence; became the concision rule |
| 2026-07-16 | meetsmore/meetsone#24618 | F2 | LOW/robustness | - | - | inline | rejected(pre-existing pattern, out of this PR's scope) | true-but-noisy; became the objective floor (introduced-by-diff) |
| 2026-07-16 | meetsmore/meetsone#24618 | F3 | MEDIUM/test-coverage | - | - | inline | rejected(test-nag on a zero-test area; suggested test asserts a deleted function) | value != truth; became the judgment gate |
