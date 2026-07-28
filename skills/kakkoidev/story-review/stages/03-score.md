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
   Never edit or interpret this file by hand - it is the deterministic floor, and
   its number must stay reproducible from a bare script call alone.
2. **Self-audit (mandatory, not optional).** Validated across 7 independent runs
   on 2026-07-28: the raw `Hits: N/M` line overstated real substantive coverage
   by roughly 20-30 percentage points in every single run, because a finding
   block can satisfy an answer-key row's regex through incidental keyword
   overlap without actually being about that row's issue (a same-block
   coincidence the per-block matcher cannot rule out - see "Known limitations"
   in SKILL.md). Do not skip this because the number "looks reasonable" - it
   looked reasonable in all 7 prior runs too, and was wrong every time.

   For every row listed under `## Matched`, re-read the actual matched finding
   block(s) against the answer-key row's plain-English `description` (not just
   its regex) and judge, in one line each: is this finding *substantively* about
   the same issue, or did it only satisfy the regex by coincidence? Write this to
   `output/self-audit.md`:
   ```
   # Self-audit of coverage-report.md

   - T<id>: GENUINE - <one line: why the matched finding really is this issue>
   - T<id>: COINCIDENTAL - <one line: what the finding is actually about instead>
   ...

   Corrected count: <N>/<total>
   ```
   `Corrected count` = the number of `GENUINE` rows, not the raw `Hits` line.
   Every row under `## Matched` must appear exactly once, whether genuine or
   not - do not omit a row because it's inconvenient. Write it via `Bash`
   (e.g. a heredoc), not the `Write` tool - a harness-level guard on
   report/summary-shaped filenames has repeatedly blocked `Write` calls on this
   skill's other mandated artifacts (`findings.md`) in every run tested so far.
3. In your reply to the user, report BOTH numbers - the raw `Hits: N/<total>`
   line and the self-audited `Corrected count` - and name which known issues
   were missed and which new candidates surfaced. Never report the raw number
   alone.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/story-review --stage 03-score
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Coverage report | output/coverage-report.md | Deterministic `score-coverage` output: a `Hits: N/<total>` line, a `## Matched` list (id + description), a `## Missed` list (id + description), and a `## New candidates` list of `findings.md` blocks that matched none of the answer-key rows (empty list stated explicitly, never omitted) |
| Self-audit | output/self-audit.md | One `GENUINE`/`COINCIDENTAL` line per row in coverage-report.md's `## Matched` section, plus a `Corrected count: N/<total>` line - the real number, not the raw scorer count |
