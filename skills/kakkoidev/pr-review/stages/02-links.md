# Stage 02: Follow the link graph (depth 2)

<!-- ICM-TOOLS expect="(notion-fetch|slack_read_thread|slack_search|web_fetch|Bash)" -->
<!-- ICM-GATE tools="notion-fetch|slack_read_thread|web_fetch" run="test -s ../01-context/output/links.tsv" -->

Resolve every link from stage 01 to its content, following one hop deeper
(depth 2) - especially Notion ticket -> the external requirement/law/spec it
cites. The gate blocks any fetch until the deterministic link set exists.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Link set | ../01-context/output/links.tsv | every URL + source |
| PR context | ../01-context/output/pr-context.md | to know which links matter |

## Process
1. Read `links.tsv`. Classify each URL: notion / slack / github / web / asset
   (badge/image/CI-status - record but do not fetch).
2. Fetch the content of each non-asset link:
   - **Notion** (`notion.so`, `notion.com`): `notion-fetch` (URL or id). From the
     fetched page, extract its outbound links and fetch the requirement/law/spec
     ones (depth 2) - this is the point of the skill.
   - **Slack**: `slack_search` to resolve channel + ts, then `slack_read_thread`.
   - **Web**: `bash ~/.agents/skills/kakkoidev/pr-review/tools/fetch-web <url>`.
     If it prints `WALLED-OFF`, retry once with WebFetch. If still unreachable,
     mark it `WALLED-OFF`.
3. Every link in `links.tsv` MUST appear in the output with a disposition:
   `resolved` (with a content summary + any depth-2 links found), `walled-off`
   (auth-required, unreachable), or `skipped:<reason>` (asset/duplicate). No link
   is silently dropped.
4. Surface to the user any `walled-off` link that looks load-bearing (a Notion
   ticket or a cited requirement), so they know what context is missing.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/pr-review --stage 02-links
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Link graph | output/link-graph.md | One section per `links.tsv` URL: url, type, source, disposition (`resolved`/`walled-off`/`skipped:<reason>`), a content summary when resolved, and any depth-2 links discovered (each with its own summary). A "Requirements" subsection collecting the authoritative external specs/laws found via Notion tickets. Every input link is accounted for. |
