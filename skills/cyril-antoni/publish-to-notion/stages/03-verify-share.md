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
4. Write `output/verify-receipt.md`: page URL, a per-check list (body / tables / mermaid /
   links), the sharing state ("private - intended" or "shared - confirmed by human"), and a
   final line that is exactly `VERIFIED: PASS` (content landed AND sharing matches audience)
   or `VERIFIED: FAIL` with what is missing.
5. Only after `VERIFIED: PASS`, give the user the final link, stating its access level. If a
   Slack/broadcast announcement is intended, remind them the link resolves only at the
   confirmed access level.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/publish-to-notion \
  --stage 03-verify-share
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Verify receipt | output/verify-receipt.md | Page URL, per-check list, sharing state, final `VERIFIED: PASS` / `VERIFIED: FAIL` |
