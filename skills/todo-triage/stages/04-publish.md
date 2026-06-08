# Stage 04: Publish

Upsert triaged items into the Task Triage database and refresh the living plan page. Private Notion. Do NOT create dated pages.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Triage rows | ../03-triage/output/rows.md | Structured items (one per task) |
| Narrative | ../03-triage/output/narrative.md | Strategic triage + sequence |

## Fixed targets (one-time setup, already done)
- Parent page **Performance Review** (private): `3751ff99-6922-81bd-b28d-c15b3924a612`
- **Task Triage** DB data source: `d478903f-73eb-42a3-a670-83208fc4681f`
  - Schema: `Task`(title), `OKR` select(① Accounting delivery / ② AI tools / ③ PO SLO / ④ Docs / Operational), `Status` select(done/next/paused/todo/cancelled), `Time` select(XS/S/M/L/XL), `Difficulty` select(Jr/Mid/Sr), `Narrative` select(H/M/L), `OKR-crit` select(H/M/L), `Verdict` select(KEEP/DELEGATE-JR/DELEGATE-MID/DELEGATE+REVIEW/PAIR/TIMEBOX/DROP), `Created` date, `Deadline` date, `Link` url, `Notes` text, `Deliverable` one-way relation -> OKR Delivery Tracker (`d84733af-4f6b-441e-af4b-bbb32882d4fa`)
- OKR Delivery Tracker + OKR Quarters scorecard are nested under the parent. Leave them untouched (they feed the scorecard).
- If the DB is ever missing, recreate via `notion-create-database` with the schema above.

## Process
1. **Upsert** each triaged item into the Task Triage data source. Stable key = `Link` (URL) if present, else `slug(OKR + Task title)`.
   - Query the DEDICATED UNFILTERED view `All (skill upsert)` (view id `3751ff99-6922-81fe-9b21-000c835c125c`, page_size 100, follow `has_more`) to map key -> page_id. NEVER query the Default view: it can carry user filters (seen in practice: Verdict=DELEGATE-JR) that hide rows, which makes the upsert think rows are missing and create DUPLICATES.
   - Matched row: `notion-update-page` `update_properties` for CHANGED fields only.
   - Unmatched: `notion-create-pages` with `parent` = `{data_source_id}`.
   - Selects by exact option name; dates via expanded keys (`date:Created:start` + `date:Created:is_datetime`=0); never invent `Deadline`.
   - Idempotent: same snapshot re-run = no-op. NEVER create duplicates.
   - Items that vanished from the snapshot since last run: leave as-is (do not delete).
2. **Refresh the DB description** (this IS the living plan narrative). `notion-update-data-source` `description` on `d478903f-73eb-42a3-a670-83208fc4681f` with the condensed strategic triage (arithmetic, hidden clocks, decision blockers) + this cycle's calls + sequence. The Task Triage DB is the living page: there is NO separate narrative page and NO dated pages.
3. **Verify**: re-query the DB (row count == triaged count minus flagged duplicates) and confirm the description is set.

## Notes
- Private page/DB: contains delegation calls + candid framing. Do not share without the user's say-so.
- The Triage DB is the PLANNING layer; the Delivery Tracker + Quarters are the MEASUREMENT layer. Keep them separate; only the one-way `Deliverable` relation links them.

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Publish record | output/published.md | DB URL, counts (created / updated / skipped), description-updated?, verification notes |
