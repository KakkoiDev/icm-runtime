# Stage 03: Tighten

<!-- ICM-TOOLS expect="(Read|Write)" -->

Cut to length, make the claims honest, and produce any per-destination variant from the same
substance. This is where the report earns "short and actionable."

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Report draft | ../02-draft/output/report.md | the draft to tighten |
| Frame | ../01-frame/output/frame.md | the target altitude, read-time, names policy |

## Process
1. Cut to the target read-time from the frame. At a 10-second altitude, confirm a reader gets
   the decision in one skim; delete anything that does not serve it.
2. Overclaim pass: replace "working solution" / "done" / "solved" with honest wording
   ("approach", "on the way to", "proposed") wherever nothing is built. Add a one-line "what
   this does not cover" if it is missing.
3. Remove every em dash; kill filler, throat-clearing, and encouragement closers.
4. Checklist: thesis first; no-context intro present; at most one diagram per idea; at most one
   ground-rule callout; idea-disposition present; names policy honored.
5. If the report needs more than one destination (e.g. a long-form doc and a chat TL;DR),
   produce each variant from the SAME substance - do not re-derive. Name them by destination.
6. Write `output/report-final.md` (the canonical report), plus any `output/report-<dest>.md`
   variants, plus a final line that is exactly `STYLE: PASS` or `STYLE: FAIL` with the
   checklist items that failed.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/draft-report \
  --stage 03-tighten
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Final report | output/report-final.md | tightened canonical report, ready to hand to a publish skill or paste |
| Destination variants | output/report-<dest>.md | optional per-destination cuts from the same substance |
| Style check | output/report-final.md (last line) | `STYLE: PASS` or `STYLE: FAIL` + failed items |
