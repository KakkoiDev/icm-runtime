# Known limits of this demo (read this, it is the honest part)

This skill shows what the ICM runtime can do offline. It deliberately does NOT show
some things, and some runtime behaviours have real edges. Stating them is the point:
a demo that hides its blind spots teaches the wrong lesson.

## What the offline demo cannot show
- **A satisfied `ICM-CALL` execution spec.** `<!-- ICM-CALL tool="X" args="..." -->`
  makes `audit` REQUIRE that tool was actually called with those args in the stage's
  window (it reads `tool-args.jsonl`, populated by the enforcement hook on real tool
  calls). An offline demo makes no real tool calls, so any spec it hosted would always
  show as a deviation and the run's audit would never be clean. That is why this
  skill carries an `ICM-GATE` (checkable offline) but NO `ICM-CALL`. The construct is
  explained in `SKILL.md` and shown working in
  `cyril-antoni/publish-to-notion/stages/03-verify-share.md`
  (`<!-- ICM-CALL tool="notion-fetch" args="id" -->`, verified by audit there).
- **Live MCP / web enforcement.** The showcase calls `gate-check --tool demo_publish`
  itself; it never makes a real tool call. So it proves the gate LOGIC (matching,
  scoping, the checker, tamper-evidence) but not that a harness PreToolUse hook fired
  on a genuine `notion-create-pages` call. For that, install hooks
  (`./installer.sh --hooks`) and run a real integration skill like
  `cyril-antoni/publish-to-notion`. Cross-harness normalization is shown against a
  fabricated `mcp__claude_ai_Notion__demo_publish` string, not a real Notion call.
- **Real token counts in the sandbox.** The stage-02 sandbox sets `$HOME` to a
  throwaway dir, so `find_transcript` matches nothing and `stage-done` records
  `counts: estimated`, `transcript_source: none` with null token fields. Honest
  four-field counts come from the demo's OWN run in stage 03, which has a live
  session transcript. Do not read the sandbox's zero counts as real telemetry.

## Real runtime edges worth knowing (not bugs in this skill)
- **Two distinct tamper layers, different detectors.** Editing a FROZEN file
  (`CONTEXT.md`, a checker, a tool) is caught by `gate-check`/`audit` via the
  `.manifest` (`contract tampered`). Editing a SEALED file (`events.jsonl`,
  `run.json`, `.manifest` itself) is caught by `verify-seal` (`SEAL MISMATCH`).
  Neither detector catches the other layer's edit: a `CONTEXT.md` edit leaves the
  seal OK (the `.manifest` file is unchanged), and an `events.jsonl` edit leaves the
  manifest OK. You need both, and the demo shows both.
- **Tamper evidence, not prevention.** Seals and the manifest convert a silent edit
  into a visible mismatch; they do not stop an agent deleting the run dir or feeding
  the checker fake inputs. The threat model is a negligent agent, not a malicious
  one. Committing `.icm/` (or at least `.icm-seals.log`) makes edits loud in git.
- **Gates need a registered adapter to enforce.** Without `installer.sh --hooks`,
  gates are advisory: nothing consults `gate-check` before a tool call. `audit`
  surfaces a "gates were advisory only" banner when a run declares gates but no
  gate-check records exist. The offline tour calls `gate-check` directly, so it works
  regardless of whether a hook is installed.
- **Script stages are opaque to tool auditing.** Each stage here drives a `tools/`
  script (`run-report`, `sandbox-tour`, `close-run`) under one `Bash` call - a
  deliberate trade so the evidence files are reproducible and eval-checkable rather
  than model prose. The cost: `audit` sees "Bash ran" for the stage, not which script
  or what it did. That is the right split for a demo (the deterministic surface is
  covered by `eval/`), but for a skill whose per-call arguments must be verified, use
  an `ICM-CALL` execution spec on a real harness tool instead of burying the work in a
  script.
