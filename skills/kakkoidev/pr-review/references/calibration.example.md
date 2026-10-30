# Inline-comment calibration log (format)

The real log is local, untracked data - its rows name the reviewed PRs:
`~/.config/icm/pr-review-calibration.md`. Copy this file there and append to the copy.

Ground truth for the value gate: what actually happened to each posted finding.
Append one row per finding after the author/reviewer responds (harvest the raw
threads with `tools/gather-review-feedback <owner>/<repo> <PR#>`, then classify).
Verdicts: `accepted` (author acted or agreed), `rejected(<reason>)` (author pushed
back and was right), `disputed` (pushed back, unresolved), `ignored` (no response).
A finding shape rejected twice becomes a demotion reason in the stage-04 floor or a
scar - that is the point of this file. Precision per PR = accepted / posted.

| date | PR | finding | severity/category | posted as | verdict | lesson |
|------|----|---------|-------------------|-----------|---------|--------|
