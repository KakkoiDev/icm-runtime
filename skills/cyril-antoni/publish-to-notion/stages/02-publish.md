# Stage 02: Publish the page

<!-- ICM-TOOLS expect="(notion-create-pages|notion-update-page)" -->
<!-- ICM-GATE tools="notion-create-pages|notion-update-page" run="test -s ../01-render/output/page.md" -->

Create the new page, or update the existing one, with the rendered body. The gate guards a
PRE-write invariant only: a rendered body must exist before any Notion write (you cannot
publish nothing). A PreToolUse gate runs BEFORE the tool, so it cannot check a post-write
fetch-back receipt - do NOT gate the write on verification. The fetch-back is enforced in
stage 03 and by `icm.sh audit`.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Page body | ../01-render/output/page.md | The Notion-flavored markdown to write |
| Target spec | ../01-render/output/target.md | create vs update, parent/page_id, title |

## Process
1. Read `target.md`.
2. If mode is create: call `notion-create-pages` with the parent from target.md (omit `parent`
   only if a private workspace page is genuinely intended), the title in `properties`, and
   `content` = the body of `page.md`. Capture the returned page URL and id.
3. If mode is update: prefer `replace_content` with `new_str` = the body for a full rewrite.
   For a surgical edit use `update_content`, building each `old_str` from a FRESH `notion-fetch`
   of the current page (Notion normalizes URLs/markers, so a previously-sent string will not
   match). Capture the page URL and id.
4. In every case, pass REAL newlines and real indentation in the content - never `\n` or `\t`
   escape text. Escapes get taken literally and can collapse the page.
5. Write `output/publish-receipt.md`: page URL, page id, mode (created/updated), and a one-line
   note of what was written or which sections were replaced.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/publish-to-notion \
  --stage 02-publish
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Publish receipt | output/publish-receipt.md | Page URL, page id, create/update, what was written |
