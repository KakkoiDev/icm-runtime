# Stage 01: Gather (body only, no comments)

<!-- ICM-TOOLS expect="(mcp__claude_ai_Notion__notion-fetch|mcp__notion__API-retrieve-page-markdown|Bash)" -->

Fetch the target Notion page's BODY ONLY, and pull deterministic schema ground
truth for the named entities out of the target repo. This stage must never see
the page's comments/discussions - the whole point of this skill is a genuine blind
review, not a lookup against answers already known.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Target page id/URL | given at invocation | the story to review |
| Target repo root | given at invocation | where to grep for schema ground truth |
| Entity names | given at invocation, space-separated | which names `tools/gather-schema-facts` and `tools/gather-impl-facts` grep for - domain entities AND the infrastructure types the doc's capability claims lean on (see step 2b) |
| Parent epic id/URL | given at invocation, OPTIONAL | if given, used to find sibling stories for lens L2's grounding (step 4) |

## Process

0. **Write the target id, before anything else.** Before fetching anything:
   ```bash
   echo "<target-page-id>" > <run>/01-gather/output/target-id.txt
   ```
   This is the ONLY thing another run is ever allowed to read about your run (see
   below) - a bare id, no content, no findings.

0b. **Prior-run check (deterministic).** From the project root:
   ```bash
   ~/.agents/skills/kakkoidev/story-review/tools/check-prior-runs \
     .icm/kakkoidev/story-review <this-run-dir-name> <target-page-id> \
     > <run>/01-gather/output/prior-runs.tsv
   ```
   `<this-run-dir-name>` is the basename of the run path `icm.sh init` printed (so
   the tool excludes your own run). The tool reads ONLY other runs' `target-id.txt`
   files - never their findings, never their story body - so this disclosure is
   safe by construction.

   **HARD RULE, for this stage and every later stage in this run, no exception:**
   never list, glob, or read any file under any `.icm/kakkoidev/story-review/`
   directory other than your own run's. Not even after you've written your own
   findings. The answer key already supplies ground truth for scoring - there is
   never a legitimate reason to reconcile against a predecessor run's output the
   way a evolving-target skill might. If you catch yourself about to `ls`, `find`,
   `cat`, or `Read` anything under a sibling timestamp directory, stop - that is
   exactly the leak this rule exists to close. `prior-runs.tsv`'s existence and
   count is disclosed to stage 02; its content is never opened.

1. Fetch the target page with `mcp__claude_ai_Notion__notion-fetch`. Do **not** pass
   `include_discussions: true`. Do **not** call `notion-get-comments` on this page,
   now or later in this run. Write the page's body markdown (properties + content,
   as returned) to `output/story-body.md` verbatim - do not summarize or trim it;
   stage 02 needs the full text to catch wording issues, not your paraphrase of it.

   **If `mcp__claude_ai_Notion__notion-fetch` is not in your tool registry** (known:
   this happens for every session spawned as a separate dispatched process - e.g.
   `tmux-agent-mesh` panes - even when `claude mcp list` shows the connector
   "Connected"; it's an OAuth-connector attachment gap specific to non-interactive
   process spawns, not a token problem, and there is no local fix for it), use
   `mcp__notion__API-retrieve-page-markdown` instead. It is body-only by
   construction (no `include_discussions`-equivalent parameter exists to
   accidentally set), so blindness holds automatically. Two things to know before
   using it:
   - It authenticates as a separate integration identity (an API-key bot, not your
     personal OAuth login), so it can only read pages explicitly shared with that
     integration. If it 404s with "Make sure the relevant pages... are shared with
     your integration," that is a real, unfixable-by-you access gap, not a stage
     failure to route around - stop and report exactly which page id(s) need
     sharing (the target and, if given, the parent epic). Do not try another tool
     as a workaround; there isn't a safe one.
   - It does not return page properties, only content - the written `story-body.md`
     will be content-only, not "properties + content." If a story's Description/
     rationale prose lives partly in a property rather than in the body, note that
     gap explicitly rather than silently treating the file as complete.
2. Run the deterministic schema grep against the target repo:
   ```bash
   ~/.agents/skills/kakkoidev/story-review/tools/gather-schema-facts <repo-root> <entity1> [entity2 ...] \
     > <run>/01-gather/output/schema-facts.md
   ```
   If the repo has no schema file matching any named entity, the script says so
   explicitly in the output - that is a valid (if thin) result, not a stage failure.

2b. **Implementation facts (deterministic).** A `model X { ... }` block is not
   enough ground truth for L5, and this is the single highest-value gap ever
   found in this skill: in a real review, six findings sat at "plausible" until
   someone read actual code, and one was *partly refuted* by it. `schema-facts.md`
   is structurally blind to enums, derived state, and existing UI/service
   behavior. Run:
   ```bash
   ~/.agents/skills/kakkoidev/story-review/tools/gather-impl-facts <repo-root> <name1> [name2 ...] \
     > <run>/01-gather/output/impl-facts.md
   ```
   **Widen the name list before you run it.** The entity list that came in at
   invocation is almost always too narrow, because it names what the story is
   about, not what the story *assumes*. Read `story-body.md` first, then add a
   name for every capability the doc leans on but does not define - the
   custom-field target type, the permission enum, the phase/status type, the
   line-item container. That widening is what produces the load-bearing negative
   facts: "`OrderLine` is referenced by no source file" and "`CustomFieldTarget`
   has no `Order` member" are only evidence because something explicitly looked.

   Read the three sections per name for what they are:
   - `enum <name>` present -> the type exists; its member list is ground truth for
     any doc claim about allowed values.
   - `<name> as a member of another enum` EMPTY -> the doc assumes a capability the
     type system does not support yet. This absence is a finding, not a gap in the
     tool.
   - `Referencing files` -> where the current behavior actually lives. If the doc
     says "an extension of the existing X," the top files here are what X really
     does; L10 cannot be answered without reading them.

   The referencing-file list is capped and says so. A capped list is not a clean
   one - if a finding turns on what a file does, open the file.

3. If either output ends up empty, do not silently continue: `story-body.md` empty
   means the fetch failed (wrong id, no access) - stop and report it; an empty
   `schema-facts.md` beyond the tool's own "not found" line means the entity names
   were wrong - re-check them against the doc before moving on.
4. **Sibling grounding for L2 (only if a parent epic id was given).** A
   cross-document contradiction is invisible to lens L2 unless the *other*
   document's actual current text is on hand - the target story rarely links to
   the sibling that actually governs a rule it touches (e.g. an archiving rule
   defined in a different sibling story than the one you're reviewing).
   4a. Fetch the parent epic's body (same rule as step 1 - body only, no comments).
       Extract its full list of child/sub-task story ids and titles (excluding the
       target itself) into `output/epic-siblings.tsv` (`id<TAB>title`, one row per
       sibling) BEFORE making any relevance judgment - this is the complete
       candidate set, and every row in it must get a disposition in the next
       sub-step (nothing may be silently absent from consideration).
   4b. For each row in `epic-siblings.tsv`, judge whether its TITLE plausibly
       overlaps this target's topic (archiving, permissions, editing, phase/status
       transitions, viewing/listing - match on the concept, not exact words). Fetch
       the body (still no comments) of the top matches, capped at 4 for budget, and
       write each to `output/sibling-<slug>.md` (slug = a short kebab-case tag,
       e.g. `sibling-archive-change-order.md`).
       **Known tool-shape caveat, discipline required:** the epic's `Sub-task`
       property exposes bare URLs, no titles - getting each sibling's title (to make
       the 4b judgment at all) requires fetching its full body via `notion-fetch`,
       even for the 3+ siblings that will NOT make the budget cut. That content
       reaches your context whether or not you persist it. Treat any sibling body
       you did not write to `output/sibling-*.md` as UNSEEN for every later step,
       the same discipline as an unread comment - never let it inform an L2 finding,
       even unattributed. If you notice yourself reasoning from a skipped sibling's
       content, that is a discipline lapse to self-correct, not a free extra hint.
   4c. Write `output/siblings-fetched.md`: **every single row from
       `epic-siblings.tsv` must appear**, each as either `FETCHED: <id> <title> -
       <topic-overlap reason>` or `SKIPPED: <id> <title> - <reason>` (a real reason
       - "lower overlap than the kept 4, budget" is fine; silent omission is not).
       A row present in `epic-siblings.tsv` but absent from `siblings-fetched.md`
       is a stage defect stage 03's coverage check will catch.

## Determinism note

Step 4a's extraction and 4c's per-row disposition requirement exist so an
`eval-heldout` check can mechanically verify nothing was silently dropped from
sibling consideration (mirrors `pr-review`'s link-coverage guarantee). The
relevance JUDGMENT in 4b stays model-mediated - only the completeness of
*accounting for every candidate* is enforced.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/story-review --stage 01-gather
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Target id | output/target-id.txt | Single line: the literal target page id given at invocation. Written FIRST, before any fetch. The only artifact another run may ever read about this run. |
| Prior runs | output/prior-runs.tsv | `tools/check-prior-runs` output: `run_dir<TAB>target_id<TAB>same_target` per other run found, or just the header row if none exist. Metadata only - target ids, never content. |
| Story body | output/story-body.md | The target page's full body (properties + content), verbatim from `notion-fetch`, **comments/discussions never included** |
| Schema facts | output/schema-facts.md | Deterministic `gather-schema-facts` output: for each named entity, its real field list from the target repo's schema, or an explicit "not found" line |
| Implementation facts | output/impl-facts.md | Deterministic `gather-impl-facts` output: per name, its own enum block (or "not found"), whether it appears as a member of any other enum (an empty result being the load-bearing fact), and the referencing source files with hit counts. Ground truth for L5 and L10. |
| Epic siblings | output/epic-siblings.tsv | Present only if a parent epic id was given: `id<TAB>title` for every child/sub-task of the epic excluding the target itself - the complete candidate set, before any relevance judgment. |
| Sibling manifest | output/siblings-fetched.md | Present only if a parent epic id was given: every row from `epic-siblings.tsv`, each as `FETCHED: ...` (with topic-overlap reason) or `SKIPPED: ...` (with reason). A single line stating "no parent epic id given - L2 has no sibling grounding this run" if step 4 did not run at all. |
| Sibling bodies | output/sibling-*.md | 0-4 files, one per sibling story fetched for L2 grounding; body only, no comments. Absent entirely if no parent epic id was given. |
