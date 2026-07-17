# Inline-comment calibration log

Ground truth for the value gate: what actually happened to each posted finding.
Append one row per finding after the author/reviewer responds (harvest the raw
threads with `tools/gather-review-feedback <owner>/<repo> <PR#>`, then classify).
Verdicts: `accepted` (author acted or agreed), `rejected(<reason>)` (author pushed
back and was right), `disputed` (pushed back, unresolved), `ignored` (no response).
A finding shape rejected twice becomes a demotion reason in the stage-04 floor or a
scar - that is the point of this file. Precision per PR = accepted / posted.

| date | PR | finding | severity/category | posted as | verdict | lesson |
|------|----|---------|-------------------|-----------|---------|--------|
| 2026-07-16 | meetsmore/meetsone#24618 | F1 | LOW/scope | inline (multi-bullet) | accepted | legit ("required context") but verbose - one engineer-natural sentence; became the concision rule |
| 2026-07-16 | meetsmore/meetsone#24618 | F2 | LOW/robustness | inline | rejected(pre-existing pattern, out of this PR's scope) | true-but-noisy; became the objective floor (introduced-by-diff) |
| 2026-07-16 | meetsmore/meetsone#24618 | F3 | MEDIUM/test-coverage | inline | rejected(test-nag on a zero-test area; suggested test asserts a deleted function) | value != truth; became the judgment gate |
