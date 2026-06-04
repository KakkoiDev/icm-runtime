# Stage 03: Triage

Score every item and produce the opinionated planning doc.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Enriched metadata | ../02-enrich/output/enriched.md | Full file |
| Normalized todos | ../01-ingest/output/todos.md | For reconciliation |

## Process
1. Score each item:
   - **Time**: XS / S / M / L / XL (mid-level baseline).
   - **Difficulty**: Jr / Mid / Sr (from domain depth + blast radius + ambiguity).
   - **Impact = TWO separate axes**:
     - **Narr** (review-narrative value): does doing this personally leave a trace? Durable/visible/novel artifact or leadership signal. H/M/L.
     - **OKR-crit** (delivery risk): weighted by the OKR's % and whether dropping/slipping it breaks the OKR's success criteria. H/M/L.
   - **Verdict** derived from the two axes (NOT from task type):
     - High Narr -> KEEP (your trace)
     - Low Narr + High crit -> DELEGATE+REVIEW (supervise; it can sink an OKR)
     - Low Narr + Med crit -> DELEGATE-MID (domain) or DELEGATE-JR (isolated)
     - Low Narr + Low crit -> DELEGATE-JR / TIMEBOX / DROP
2. Build the **strategic triage** (the value-add, put it ABOVE the tables):
   - The arithmetic: total effort vs one person's capacity across all OKRs -> delegation is forced, not optional.
   - Hidden clocks: criteria like "each tool >=50% team >=1 month" are deadlines in disguise; flag every metric that needs calendar time.
   - Decision blockers: an OKR frozen behind a decision/sign-off (not labor) - call it out as critical-path.
   - Verdict buckets: KEEP / DELEGATE-NOW (JR) / DELEGATE+REVIEW / TIMEBOX-DROP.
   - Suggested sequence: this week (you) / delegate now / defer.
3. Reconcile: every line from todos.md appears exactly once (or is flagged as a duplicate). Count in == count out.
4. Sanity-check: anything tagged DELEGATE-JR that sits on an OKR critical path -> re-tag DELEGATE+REVIEW.
5. Emit `rows.md` in the EXACT Task Triage DB vocabulary (select option names must match the schema verbatim) so stage 04 upserts without remapping. Put all prose in `narrative.md`.

## Rules
- Never invent deadlines (carry "none set" through from enrich).
- Be opinionated: every row gets a verdict; the doc gets a sequence.
- Push back in writing where the user's framing is risky (e.g. "delegate all bug fixes" when bug fixes ARE a weighted OKR).

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Triage rows | output/rows.md | One row per item in the Task Triage DB vocabulary: Task, OKR (① Accounting delivery / ② AI tools / ③ PO SLO / ④ Docs / Operational), Status (done/next/paused/todo), Time (XS/S/M/L/XL), Difficulty (Jr/Mid/Sr), Narrative (H/M/L), OKR-crit (H/M/L), Verdict, Created, Deadline, Link, Notes. Ranges (M-L, Mid/Sr) -> lower bound in the field, full range in Notes. |
| Narrative | output/narrative.md | Prose that does NOT fit DB rows: legend, strategic triage (arithmetic, hidden clocks, decision blockers), verdict buckets, suggested sequence, risk notes |
