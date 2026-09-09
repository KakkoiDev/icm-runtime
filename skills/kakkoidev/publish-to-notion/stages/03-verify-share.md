# Stage 03: Verify and share

<!-- ICM-TOOLS expect="(notion-fetch)" -->
<!-- ICM-GATE tools="notion-fetch" run="test -s ../02-publish/output/publish-receipt.md" -->
<!-- ICM-CALL tool="notion-fetch" args="id" -->

Confirm the write actually landed, then make sure the page is readable by its intended
audience before any link is handed out. Notion returns success even when it silently drops an
edit, so the fetch-back is the only proof the page says what you think. And a private-page link
is worthless to anyone but you - resolve sharing before emitting the link.

The gate guards a PRE-condition only: a publish receipt must exist before verifying. The
fetch-back itself is a mandatory Process step checked by `icm.sh audit`, not by the gate (a
PreToolUse gate cannot inspect a result that does not exist until after the fetch).

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Publish receipt | ../02-publish/output/publish-receipt.md | Page URL + id to verify |
| Target spec | ../01-render/output/target.md | The intended audience |
| Page body | ../01-render/output/page.md | What the page is supposed to contain |

## Process
1. `notion-fetch` the page by id/URL. Compare against `page.md`: confirm the body, every
   `<table>`, every mermaid block, and every link are present. Note anything missing or
   mangled (silent-dropped edits, broken tables, unrendered mermaid).
2. If anything is missing, the publish did not fully land: report exactly what is missing and
   stop with `VERIFIED: FAIL`. (Fixing it is a re-run of stage 02, not this stage.)
3. Resolve sharing against the audience in `target.md`:
   - Audience "just me": private is fine; say so.
   - Audience is a team or anyone at the org: the page must be shared. There is no MCP
     permission API, so instruct the human to set it in the Notion UI (move to the teamspace,
     or Share -> "anyone at <org> can view"), and WAIT for them to confirm.
4. Full width and mermaid display, for a bilingual page (captain's standing rule, 2026-09-08).
   Confirm from the fetched body that every `<table>` carries BOTH `fit-page-width="true"` and a
   `<colgroup>` of explicit `<col width="...">`. A table missing the `<colgroup>` renders narrow
   even with the attribute set; that is a defect and sends you back to stage 01.
   Page-level full width and mermaid preview-only display are permanently MANUAL by the captain's
   ruling of 2026-09-08. Neither is settable through the API and neither is reported back by
   `notion-fetch`. Do not attempt a workaround. Never assert either is set. Just record both in
   the receipt as outstanding manual steps for the human: page `...` menu "Full width", and the
   per-block display toggle on each mermaid diagram.
5. Write `output/verify-receipt.md`: page URL, a per-check list (body / tables / mermaid /
   links), the sharing state ("private - intended" or "shared - confirmed by human"), the
   full-width state for a bilingual page, and a
   final line that is exactly `VERIFIED: PASS` (content landed AND sharing matches audience)
   or `VERIFIED: FAIL` with what is missing.
6. Only after `VERIFIED: PASS`, give the user the final link, stating its access level. If a
   Slack/broadcast announcement is intended, remind them the link resolves only at the
   confirmed access level.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/publish-to-notion \
  --stage 03-verify-share
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Verify receipt | output/verify-receipt.md | Page URL, per-check list, sharing state, final `VERIFIED: PASS` / `VERIFIED: FAIL` |
