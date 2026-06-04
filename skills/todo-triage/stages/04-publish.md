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
  - Schema: `Task`(title), `OKR` select(① Accounting delivery / ② AI tools / ③ PO SLO / ④ Docs / Operational), `Status` select(done/next/paused/todo), `Time` select(XS/S/M/L/XL), `Difficulty` select(Jr/Mid/Sr), `Narrative` select(H/M/L), `OKR-crit` select(H/M/L), `Verdict` select(KEEP/DELEGATE-JR/DELEGATE-MID/DELEGATE+REVIEW/PAIR/TIMEBOX/DROP), `Created` date, `Deadline` date, `Link` url, `Notes` text, `Deliverable` one-way relation -> OKR Delivery Tracker (`d84733af-4f6b-441e-af4b-bbb32882d4fa`)
- OKR Delivery Tracker + OKR Quarters scorecard are nested under the parent. Leave them untouched (they feed the scorecard).
- If the DB is ever missing, recreate via `notion-create-database` with the schema above.

## Process
1. **Upsert** each triaged item into the Task Triage data source. Stable key = `Link` (URL) if present, else `slug(OKR + Task title)`.
   - Query the data source to map key -> existing page_id.
   - Matched row: `notion-update-page` `update_properties` for CHANGED fields only.
   - Unmatched: `notion-create-pages` with `parent` = `{data_source_id}`.
   - Selects by exact option name; dates via expanded keys (`date:Created:start` + `date:Created:is_datetime`=0); never invent `Deadline`.
   - Idempotent: same snapshot re-run = no-op. NEVER create duplicates.
   - Items that vanished from the snapshot since last run: leave as-is (do not delete).
2. **Refresh the living narrative page** (one stable page under the parent, e.g. "Triage - Current Plan"): `notion-update-page` `replace_content` with the strategic triage + sequence + risk notes, and embed the Task Triage DB as a linked/grouped view. `replace_content` is safe here (page has no child pages). Do NOT create a new dated page.
3. **Verify**: re-query the DB (row count == triaged count minus flagged duplicates) and `notion-fetch` the narrative page.

## Notes
- Private page/DB: contains delegation calls + candid framing. Do not share without the user's say-so.
- The Triage DB is the PLANNING layer; the Delivery Tracker + Quarters are the MEASUREMENT layer. Keep them separate; only the one-way `Deliverable` relation links them.

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Publish record | output/published.md | DB URL, narrative page URL, counts (created / updated / skipped), verification notes |
