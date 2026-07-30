# Stage 03: Score (deterministic)

<!-- ICM-TOOLS expect="(Bash)" -->

Measure stage 02's findings two ways, both deterministic - no model judgment in
either number, so both are reproducible from bare script calls:

- **Coverage** against the frozen answer key, but ONLY when this run's target is
  the story that key was extracted from. Otherwise the scorer refuses to emit a
  number, by design (see step 1).
- **Grounding + refutation survival**, which is target-independent and therefore
  the number that always exists.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Findings | ../02-blind-review/output/findings.md | this run's blind-review output |
| Target id | ../01-gather/output/target-id.txt | which story was reviewed |
| Answer key | ../../references/answer-key.tsv (frozen) | the real, known issue set to score against |
| Answer key's target | ../../references/answer-key-target.txt (frozen) | the ONE story the key was extracted from |

## Process
1. Run the deterministic scorer, **always passing both id files** - they are what
   make the guard work:
   ```bash
   ~/.agents/skills/kakkoidev/story-review/tools/score-coverage \
     ../02-blind-review/output/findings.md \
     ~/.agents/skills/kakkoidev/story-review/references/answer-key.tsv \
     ../01-gather/output/target-id.txt \
     ~/.agents/skills/kakkoidev/story-review/references/answer-key-target.txt \
     > output/coverage-report.md
   ```
   Never edit or interpret this file by hand - it is the deterministic floor, and
   its number must stay reproducible from a bare script call alone.

   **If the report says `Hits: n/a`, that is correct behavior, not a failure.**
   The answer key is bound to one story; scored against a different one it counts
   shared domain vocabulary. This happened for real: a sibling story was scored
   against the US-01 key, the number looked entirely reasonable, and only a human
   noticing the mismatch stopped it being reported as coverage. Do not route
   around the guard by dropping the id arguments, and do not treat `n/a` as
   permission to skip step 2 - step 2 is where a non-source target gets its
   number. Skip step 3 in this case (there are no matched rows to audit) and say
   so in one line in `output/self-audit.md`.

2. **Grounding audit (always, whatever step 1 reported).**
   ```bash
   ~/.agents/skills/kakkoidev/story-review/tools/grounding-audit \
     ../02-blind-review/output/findings.md \
     > output/grounding-audit.md
   ```
   This counts form, not truth: `Grounded: N/M` is the share of findings carrying a
   story quote, a valid `Confidence:` label, and an `Evidence:` line;
   `Survival rate: S/C` is how many candidates lived through stage 02's refutation
   pass. A perfect grounding rate says the evidence discipline held, never that the
   findings are right.
   Read the `## Ungrounded findings` section and act on it: a named finding is
   missing a field stage 02 owed it. Fixing that means editing `findings.md` (add
   the quote/evidence it should have had) and re-running this tool - not editing
   this report. If a finding genuinely cannot be grounded, its confidence is
   `Plausible` at best; say that rather than leaving the field off.
   `Survival rate: C/C` (nothing refuted) is a yellow flag on a doc of any real
   size - re-read step 11 of stage 02 before accepting it.

3. **Self-audit of coverage (mandatory whenever step 1 produced a real number).**
   Validated across 7 independent runs on 2026-07-28: the raw `Hits: N/M` line
   overstated real substantive coverage by roughly 20-30 percentage points in
   every single run, because a finding block can satisfy an answer-key row's
   regex through incidental keyword overlap without actually being about that
   row's issue (a same-block coincidence the per-block matcher cannot rule out -
   see "Known limitations" in SKILL.md). Do not skip this because the number
   "looks reasonable" - it looked reasonable in all 7 prior runs too, and was
   wrong every time.

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
   not - do not omit a row because it's inconvenient. When step 1 reported
   `Hits: n/a` there are no rows to audit: write the same file with a single line
   naming the target mismatch and `Corrected count: n/a`.
   Write it via `Bash` (e.g. a heredoc), not the `Write` tool - a harness-level
   guard on report/summary-shaped filenames has repeatedly blocked `Write` calls
   on this skill's other mandated artifacts (`findings.md`) in every run tested
   so far.
4. In your reply to the user, report the grounding numbers (`Grounded`,
   `Survival rate`) plus, when scoring applied, BOTH the raw `Hits: N/<total>`
   line and the self-audited `Corrected count`, and name which known issues were
   missed and which new candidates surfaced. Never report the raw hit number
   alone.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/story-review --stage 03-score
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Coverage report | output/coverage-report.md | Deterministic `score-coverage` output: a `Hits: N/<total>` line (or `Hits: n/a` plus a `## Not applicable` block when the run's target isn't the answer key's source story), a `## Matched` list (id + description), a `## Missed` list (id + description), a `## New candidates` list of `findings.md` blocks that matched none of the answer-key rows, and `## Ambiguous overlap` - every section present, empty lists stated explicitly, never omitted |
| Grounding audit | output/grounding-audit.md | Deterministic `grounding-audit` output: `Grounded: N/M`, `Refuted: N`, `Candidates: N`, `Survival rate: S/C`, a per-finding table, an explicit `## Ungrounded findings` list, and the confidence distribution |
| Self-audit | output/self-audit.md | One `GENUINE`/`COINCIDENTAL` line per row in coverage-report.md's `## Matched` section, plus a `Corrected count: N/<total>` line - the real number, not the raw scorer count. When coverage was `n/a`: one line naming the target mismatch plus `Corrected count: n/a` |
