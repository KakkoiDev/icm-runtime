---
name: gate-demo
description: >
  The smallest possible ICM demo: one stage, one gate. A "publish" action stays
  blocked until the stage produces output/receipt.md, then it is allowed. Files
  persist in .icm/ so you can see exactly what changed - no sandbox, no model.
---

# gate-demo

One stage, one gate. The `publish` action is blocked until `output/receipt.md`
exists; create the file and the gate lets the call through. Everything persists in
`.icm/`, so you can `ls` the run and watch the precondition appear.

This is the talk-sized demo. For the exhaustive offline self-test of every
mechanism (scoping, name normalization, seal, manifest tamper) see
`kakkoidev/icm-demo` and its `tools/sandbox-tour`.

## Demo it in 4 commands

```
ICM=~/.agents/skills/icm/runtime/icm.sh
RUN=$(bash $ICM init kakkoidev/gate-demo)          # prints the run path
bash $ICM gate-check --tool publish && echo ALLOWED || echo DENIED                # DENY: receipt.md missing
echo ok > "$RUN/01-publish/output/receipt.md"      # produce the precondition
bash $ICM gate-check --tool publish && echo ALLOWED || echo DENIED                # ALLOW
```

`publish` is a stand-in for whatever real action you gate (deploy, send, publish).
The gate is the frozen checker `checks/receipt.sh` (`test -s output/receipt.md`),
hashed into the run's `.manifest` so it cannot be weakened mid-run.

## Runtime

Driven through `icm.sh` (init, gate-check, stage-done, audit, seal) like any ICM
skill. See the `icm` runtime SKILL.md for the full contract.
