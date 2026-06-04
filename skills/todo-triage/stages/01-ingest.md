# Stage 01: Ingest

Pull the latest todo snapshot from the user's Slack self-DM and normalize it.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Slack self-DM | channel `D07HBM0CDLG` (read via `slack_read_channel`) | Most recent OKR/todo snapshot |

## Process
1. Read self-DM channel `D07HBM0CDLG`, newest first (`slack_read_channel`, limit ~10). Load the tool via ToolSearch (`select:mcp__claude_ai_Slack__slack_read_channel`) if not already available.
2. Select the todo snapshot by STRUCTURE, never by a specific OKR title. OKR titles change every cycle, so matching on text like "Accounting delivery" is brittle and WILL silently break.
   - A todo snapshot is the **most recent** message that has BOTH: (a) one or more bold OKR headers - `*OKR` immediately followed by a circled number (①②③④), and (b) several checkbox markers (`:white_square:` and/or `:white_check_mark:`).
   - EXCLUDE bot/automation posts even if more recent: anything containing `Sent using <@...|Claude>`, or starting with `:mailbox_with_mail:` (Gmail digest) or `:memo: _Slack digest_`.
   - If no message matches, report that plainly and stop - do not fall back to a digest or an arbitrary message.
   - Channel fallback: if `D07HBM0CDLG` ever fails, find the self-DM via `slack_search_users` (email `cyril.antoni@meetsmore.com`) and read that user_id as a DM.
3. Parse every line item. Capture: group (OKR①/②/③/④, Operational, or blockers), title, status marker, link(s), any inline `[YYYY-MM-DD ... JST]` timestamp, and indentation (sub-items like the Nako report-back children ④⑤①③⑥ belong to their parent).
4. Map status markers: `:white_check_mark:`=done, `:white_square:`=todo, `:arrow_forward:`=next, `:double_vertical_bar:`=paused.
5. Normalize Slack links `<url|text>` to `[text](url)`. Mark items that have no link.
6. Flag duplicates (same URL listed twice) and umbrella/child relationships (a bundle ticket + its broken-out children).

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Normalized todos | output/todos.md | Markdown grouped checklist; one row per distinct item: status, title, link, group, notes (dup / child-of / no-link / OKR weight) |
