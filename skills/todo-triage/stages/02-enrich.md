# Stage 02: Enrich

Fetch real metadata for every linked item. Titles lie; open the source.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Normalized todos | ../01-ingest/output/todos.md | Full file |

## Process
1. For each item WITH a link, fetch metadata IN PARALLEL. Batch by source and dispatch general-purpose subagents when volume is high (this list is often 40+ links):
   - **Notion** (`app.notion.com` / `notion.so`): `notion-fetch` -> creation date, due date (usually empty), Release Phase / status, 1-2 line scope, size signal.
   - **GitHub PRs** (`github.com/<owner>/<repo>/pull/<n>`): `gh pr view <n> --repo <owner>/<repo> --json number,title,state,createdAt,updatedAt,additions,deletions,changedFiles,reviewDecision,isDraft,labels` -> diff size as review-effort proxy.
   - **Google Docs**: `gws_export` / `gws_api`. **External repos**: `WebFetch` (purpose, stars/maturity, license). **Slack threads**: `slack_read_thread`.
2. For items WITHOUT a link (e.g. SLO steps, doc-writing steps, AI-tool build/measure steps), estimate scope from the OKR context and mark "no ticket yet".
3. Per item, record: creation date, deadline (or "none"), status, scope (1-2 lines), Size (XS<0.5d / S 0.5-1d / M 2-3d / L ~1wk / XL >1wk, mid-level), DomainDepth (low/med/high), BlastRadius (isolated/cross-cutting).
4. Note file/area COLLISIONS (multiple items editing the same file) and confirm umbrella/child dedup from stage 01.

## Caveats (learned, do not relearn)
- Notion `Due` fields are almost always empty (`is_datetime=0`). Report "none"; never invent a deadline.
- Tickets carry no effort/estimate field; Size is your derivation from scope.
- `gh` CLI is authenticated. Diff size is a proxy only - weight money/migration/auth/accounting changes heavier than raw line count.
- Some links are auth-gated (e.g. internal SSO apps); report "couldn't assess", do not guess content.

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Enriched metadata | output/enriched.md | One structured block per item with the fields above; a COLLISIONS section; a DUPLICATES/UMBRELLA section |
