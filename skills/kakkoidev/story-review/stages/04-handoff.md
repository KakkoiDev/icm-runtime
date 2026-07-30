# Stage 04: Handoff (the deliverable)

<!-- ICM-TOOLS expect="(Read|Bash)" -->
<!-- ICM-GATE tools="Write" run="checks/reviewed.sh" -->

Turn the audited findings into the thing a human actually uses: a decision-owner
question list. Nothing new is discovered here - no new findings, no new lenses. If
you notice a fresh issue while writing this stage, it belongs in a later run, not
smuggled in past the refutation and grounding passes that every other finding went
through.

**Why this stage exists.** For three validated runs this skill's final artifacts
were `findings.md` (raw, engineer-facing, mixed severity) and a coverage report
(a self-test of the skill, useless to anyone reviewing the story). A human then
hand-built the actual deliverable - severity, confidence, per-AC comment targets
and a product question per row - from those files afterward, twice. Worse, on the
run where that happened, per-story reports for three of the five stories were
written to a scratchpad OUTSIDE the sealed run and were simply gone by the time
anyone looked: they were not in the archive, so those stories could not be audited
at all. The handoff is a stage so that it is sealed with the run, and so that the
work of shaping it is not redone by hand every time.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Findings | ../02-blind-review/output/findings.md | surviving `## F<n>` blocks and refuted `## R<n>` blocks |
| Grounding audit | ../03-score/output/grounding-audit.md | which findings are grounded; the confidence distribution |
| Coverage report | ../03-score/output/coverage-report.md | `## New candidates` = findings not in the frozen key (only meaningful when scoring applied) |
| Self-audit | ../03-score/output/self-audit.md | which matched rows were coincidental |
| Story body | ../01-gather/output/story-body.md | for AC numbering and exact quotes |

## Process

1. **Assign a decision priority to every surviving finding.** Three values, and the
   test is about who can answer it, not how bad it is:
   - **Must raise** - engineering cannot pick a behavior without a product
     decision. Two implementers would reasonably ship different things.
   - **Should raise** - a real clarification, but a sensible default exists and is
     nameable.
   - **Optional** - wording, later-scope, or consistency.
   A `high` severity finding is not automatically `Must raise`, and a `low` one is
   not automatically `Optional`: a low-severity JA/EN wording overload is Optional,
   while a medium-severity undefined permission baseline that three sibling stories
   already depend on is Must raise. Priority tracks who must decide; severity
   tracks what breaks.

2. **Write one question per finding, addressed to the decision owner.** Not the
   finding restated as a complaint - the actual question whose answer unblocks
   implementation. "The rounding basis is undefined" is a finding; "Should the
   order amount use the tenant's rounding settings, the source estimate's, or the
   form's own?" is the question. Enumerate the real options when there are only a
   few: a question with the options listed gets answered in one pass, an open
   one comes back as another meeting.

3. **Locate each finding on the doc.** Give the AC or section identifier the
   finding attaches to (`EN AC4`, `JA AC10`, `Description`), because that is what a
   reader needs to find it. If a per-block anchor URL is available, include it; the
   fetched body does not carry block ids, so for most runs the AC identifier IS the
   locator - write `no block anchor available in the fetched body` rather than
   inventing a URL or silently leaving the column empty.

4. **Group by priority, Must raise first.** A reader who stops after the first
   section must have seen everything that blocks implementation.

5. **Carry the honesty forward.** Three things must survive into this file rather
   than being smoothed away:
   - each row's `Confidence` label, verbatim from `findings.md`;
   - any finding the self-audit marked `COINCIDENTAL` - keep the finding, drop the
     claim that it matched a known issue;
   - a `## Refuted` section listing every `## R<n>` candidate with its `Killed:`
     reason. Refuted candidates are the evidence the review had a precision pass,
     and they stop the next reviewer from regenerating them. Never omit this
     section; if nothing was refuted, say so and flag it as the yellow flag it is.

6. **State the limits explicitly.** One `## Limits` section, naming at minimum:
   what the grounding audit reported (`Grounded: N/M` and every ungrounded
   finding); whether coverage scoring applied to this target or was `n/a`; every
   lens that had no material and why; any sibling story that could not be fetched,
   so nobody reads L2 coverage as complete; and whether any `Plausible` row is
   waiting on code nobody read. A reader deciding how much to trust this file
   needs those in it, not in the run's telemetry.

7. **Do not act on the findings.** No Notion comments, no page edits, no ticket
   updates. This file is the input to a human's decision about which questions to
   actually ask; the operator posts comments, not this stage. (This is a
   deliberate carry-over: on the real run, the reviewer prepared comment targets
   and let the human choose which to post - the alternative floods a spec page
   with unvetted AI comments.)

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/story-review --stage 04-handoff
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Handoff | output/handoff.md | `# Story review handoff: <story id>` then a `Grounded:`/`Survival rate:` line copied from the grounding audit; a `## Must raise` / `## Should raise` / `## Optional` section each containing one table with columns `Finding \| Severity \| Confidence \| Location \| Issue \| Question`, one row per surviving finding, every `## F<n>` from findings.md appearing in exactly one section; a `## Refuted` section with one row per `## R<n>` block and its `Killed:` reason (stated explicitly as empty if nothing was refuted); and a `## Limits` section per step 6. |
