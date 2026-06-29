---
name: nest-demo
description: >
  The smallest skill-in-skill example: a parent run that delegates a subtask to a
  child run (kakkoidev/nest-demo-child) via `icm.sh init --caller`. Both skills
  gate the same `publish` tool. It demonstrates caller-scoped gates - while the
  child run is open, the parent's still-failing publish gate is suspended so the
  child's legitimate publish is allowed; when the child closes, the parent's gate
  resumes. Use to see (and test) nested skill-uses-skill runs end to end.
  Triggers: "nest demo", "skill in skill", "test caller scoping".
---

# nest-demo

A parent skill that invokes a child skill as a real ICM child run. Its one stage
delegates work to `kakkoidev/nest-demo-child`, waits for it, then finishes its
own work.

## What it demonstrates

Both `nest-demo` (parent) and `nest-demo-child` gate the `publish` tool on their
own precondition. The parent's precondition (`output/parent-evidence.md`) is NOT
met while it is delegating, so its publish gate is failing. Caller-scoping means:
while the child run it invoked is open, the parent's gate is **suspended** (the
child is doing the work), so the child - whose own gate passes - may publish.
Once the child closes, the parent's gate resumes and blocks the parent's own
publish until the parent produces its evidence. The parent is still
tamper-checked while suspended.

## Run it (model-driven)

```
icm.sh init kakkoidev/nest-demo
```
Then execute `01-delegate`: `init` the child with `--caller`, run the child to
`stage-done` + `seal`, then write `output/parent-evidence.md` and publish.

## Test it (deterministic, offline)

```
icm.sh eval kakkoidev/nest-demo
```
`eval/nesting.test.sh` drives the full nested `init` -> `gate-check` ->
`stage-done` sequence against the real parent and child skills and asserts the
suspend / allow / resume transitions. No model required.

## Reference
- `stages/01-delegate.md` - the parent stage, its publish gate, and the
  delegation steps.
- `kakkoidev/nest-demo-child` - the child skill.
