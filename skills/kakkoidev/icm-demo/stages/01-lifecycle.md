# Stage 01: Lifecycle and tracking artifacts

<!-- ICM-TOOLS expect="(Read|Bash)" -->

Capture what `icm.sh init` already did for THIS run and what tracks it, then explain
it. The deterministic facts (stage order, next empty stage, this run's header, the
enforcement posture, and the five tracking artifacts) are captured by `tools/run-report`
so the evidence is reproducible and eval-checkable; your only job is the judgement the
script cannot do - explaining, in your reply to the user, what each artifact IS and why
it matters.

The single machine comment above is a TEMPLATE construct: `ICM-TOOLS expect="..."`
declares (as an unanchored ERE) the harness tools this stage is expected to use, which
`icm.sh audit` matches against the tool calls recorded in this stage's window.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Run facts | `tools/run-report` (reads this run's `.icm/` state) | stage order, next, run.json, gate-status, the 5 artifacts |

## Process
1. From the PROJECT ROOT (where you ran `icm.sh init` - do NOT cd into the stage dir;
   `run-report` reads `.icm/` at the project root), capture the run facts into this
   stage's output file. `<run>` is the run path `icm.sh init` printed to stdout:
   ```bash
   ~/.agents/skills/kakkoidev/icm-demo/tools/run-report > <run>/01-lifecycle/output/lifecycle.md
   ```
   (`init` already created `<run>/01-lifecycle/output/`; see the Conventions in SKILL.md.)
2. In your reply to the user, explain the lifecycle: what `init` froze (each stage's
   `CONTEXT.md` plus the skill's `checks/` and `tools/`, all hashed into a sha256
   `.manifest`), and one line on what each of the five tracking artifacts IS. Point to
   the captured values in `lifecycle.md`; do not retype them.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/icm-demo --stage 01-lifecycle
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Lifecycle evidence | output/lifecycle.md | Deterministic `run-report` capture: stage order, next, this run's run.json, gate-status posture, the 5 tracking artifacts |
