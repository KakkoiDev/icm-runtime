# Stage 03: Score (deterministic)

<!-- ICM-TOOLS expect="(Bash)" -->

Score stage 02's findings against the frozen answer key. No model judgment - a
single script call, so the number is reproducible and the thing `icm-improve`
tracks phase over phase.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Findings | ../02-blind-review/output/findings.md | this run's blind-review output |
| Answer key | ../../references/answer-key.tsv (frozen) | the real, known issue set to score against |

## Process
1. Run the deterministic scorer:
   ```bash
   ~/.agents/skills/kakkoidev/story-review/tools/score-coverage \
     ../02-blind-review/output/findings.md \
     ~/.agents/skills/kakkoidev/story-review/references/answer-key.tsv \
     > output/coverage-report.md
   ```
2. Do not edit or interpret the script's output - it is the deterministic floor.
   In your reply to the user, report the headline `Hits: N/<total>` line and name
   which known issues were missed and which new candidates surfaced, but do not
   recompute or override the number.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/story-review --stage 03-score
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Coverage report | output/coverage-report.md | Deterministic `score-coverage` output: a `Hits: N/<total>` line, a `## Matched` list (id + description), a `## Missed` list (id + description), and a `## New candidates` list of `findings.md` blocks that matched none of the answer-key rows (empty list stated explicitly, never omitted) |
