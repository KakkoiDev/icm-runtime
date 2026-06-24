# Stage 02: Enforcement and tamper-evidence (the offline showcase)

<!-- ICM-TOOLS expect="Bash" -->
<!-- ICM-GATE tools="demo_publish" run="checks/ready.sh" -->

Run the offline enforcement tour and capture its real output. The two machine
comments above are TEMPLATE constructs this skill shows. What each does, and why each
is safe (inert) in this live run:

- `ICM-TOOLS expect="Bash"` declares the tool this stage actually uses (the model
  runs one Bash command). `icm.sh audit` checks this against the tool calls the
  enforcement hook recorded for this stage's time window.
- `ICM-GATE tools="demo_publish" run="checks/ready.sh"` is a real, frozen gate
  (`checks/ready.sh` is hashed into the run's `.manifest`). It is INERT in this live
  run on purpose: the only tool this stage calls is Bash, and `demo_publish` is a
  fabricated name no real tool uses, so the gate matches nothing and blocks nothing
  here. The tour below builds a THROWAWAY copy of this same run in a disposable
  directory and calls `gate-check --tool demo_publish` explicitly, so you watch the
  gate DENY then ALLOW against real frozen artifacts, without the deadlock that
  gating a real authoring tool (`Write`/`Bash`) would cause in a single stage.

This stage carries NO execution spec on purpose. An ICM-CALL comment (naming a tool
and its required arg fields) makes `audit` REQUIRE that tool was actually called with
those args in the stage window, so it can only pass when a real tool runs - which an
offline demo never does; hosting one would force a permanent audit deviation. The
literal comment syntax is omitted here too, because `audit` scrapes the frozen
contract for it and would treat even an example as a real spec. For a real, satisfied
example see `publish-to-notion` stage `03-verify-share` (an ICM-CALL for
`notion-fetch` requiring arg `id`), and `SKILL.md` / `references/known-limits.md`.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Tour driver | `~/.agents/skills/cyril-antoni/icm-demo/tools/sandbox-tour` | The deterministic offline demo script (frozen into the run as `tools/sandbox-tour`) |

## Process
1. From the PROJECT ROOT, run the tour driver and capture everything it prints; its
   stdout IS the evidence. `<run>` is the run path `icm.sh init` printed (the driver
   sandboxes itself, so cwd just needs to be the project root):
   ```bash
   ~/.agents/skills/cyril-antoni/icm-demo/tools/sandbox-tour > <run>/02-enforcement/output/enforcement.md 2>&1
   ```
2. Read `<run>/02-enforcement/output/enforcement.md` and confirm it shows, in order: stage scoping (ALLOW
   while 01 is active), gate DENY (precondition unmet), cross-harness normalization
   (the `mcp__` name DENIED, proving it matched the gate), a non-gated tool (`Read`
   ALLOW), gate ALLOW (precondition met), SEAL OK, SEAL MISMATCH (a sealed file was
   edited), and a `contract tampered` DENY (a frozen file was edited). If any marker
   is missing, the runtime behaviour changed: stop and report rather than closing the
   stage on stale evidence.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/icm-demo --stage 02-enforcement
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Enforcement evidence | output/enforcement.md | The tour driver's real captured output: gate DENY/ALLOW, normalization, scoping, SEAL OK/MISMATCH, contract tamper |
