# Stage 01: Frame

<!-- ICM-TOOLS expect="(Read|Write|Grep|Glob)" -->

Decide what the report is before writing a word. Most rewrite-thrash comes from skipping this:
not deciding the altitude up front means drafting at the wrong length and redoing it.

No gate here: authoring stages all use `Write`, and a `Write`-matched gate would deadlock the
pipeline (a later stage's gate would deny this stage writing its own output). Pre-conditions
are enforced by reading the Inputs, not by a gate.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Material | Chat or a file/path | The substance to report (analysis, notes, thread, findings). You bring this. |
| Audience + altitude | Chat | Who reads it, and the target read-time (e.g. 10 seconds / 2 minutes / full spec) |
| Input ideas | Chat / thread | Any competing proposals or options the report must address |

## Process
1. Write the single decision or takeaway the reader must leave with. One sentence.
2. Fix the audience + altitude + target read-time. This governs every later choice; write it down.
3. Write the one-line thesis (the reframe or recommendation), the first thing the reader sees.
4. If there are competing input ideas, list each and tag it keep / replace / defer with a one-line reason, so every contributor is addressed.
5. Decide names-in vs names-out. If the report leaves a private draft (broadcast, shared doc), confirm with the requester - replacing or deferring a named person's idea in public reads as a callout.
6. Write `output/frame.md`.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/draft-report \
  --stage 01-frame
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Frame | output/frame.md | decision, audience, altitude + read-time, one-line thesis, idea-disposition (keep/replace/defer), names policy |
