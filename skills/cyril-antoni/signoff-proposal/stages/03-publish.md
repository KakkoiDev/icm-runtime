# Stage 03: Publish and verify

<!-- ICM-TOOLS expect="(notion-create-pages|notion-update-page|notion-fetch)" -->
<!-- ICM-GATE tools="notion-create-pages|notion-update-page" run="test -s ../02-compose/output/proposal.md" -->

Publish the proposal as a Notion sub-page under the ticket, link it from the ticket, and
verify both writes actually landed.

The gate guards a PRE-publish invariant only: a composed proposal must exist before any
Notion write (you cannot publish nothing). A PreToolUse gate runs BEFORE the tool, so it
cannot check a post-write artifact - do NOT gate the write on a fetch-back receipt, or the
write becomes unpassable (the receipt cannot exist until after the write). The fetch-back
verification is enforced as a mandatory Process step below and checked by `icm.sh audit`,
not by the gate.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Proposal | output/../02-compose/output/proposal.md | The NFM body to publish |
| Parent ticket | From 01-gather evidence.md | The page the sub-page is created under |

## Process
1. Create the Notion sub-page with `notion-create-pages`, parent `{type: page_id, page_id: <ticket>}`,
   title set, content = proposal.md body. Capture the returned sub-page URL.
2. Update the parent ticket with `notion-update-page` `insert_content` (position end): a short
   decision line + a `<mention-page url="<sub-page URL>">` link to the proposal.
3. Fetch BOTH pages back with `notion-fetch`. Confirm: the proposal body, diagram, table, and
   every source link are present; the ticket shows the decision line + the mention link.
4. Write `output/publish-receipt.md`: sub-page URL, ticket URL, a per-check list, and a final
   line that is exactly `VERIFIED: PASS` if all checks passed, else `VERIFIED: FAIL` with what is missing.
5. Tell the user: the sub-page is ready to submit for sign-off; fixed-window source links are
   snapshots; the reviewer needs read access to the source system for the links to resolve.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/signoff-proposal \
  --stage 03-publish
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Publish receipt | output/publish-receipt.md | Sub-page URL, ticket URL, per-check verification list, final `VERIFIED: PASS` / `VERIFIED: FAIL` line |
