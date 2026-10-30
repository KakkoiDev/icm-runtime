---
name: nest-demo-child
description: >
  The child half of the nest-demo skill-in-skill example. A trivial one-stage
  skill that produces an evidence file and then may publish. Invoked by
  kakkoidev/nest-demo via `icm.sh init --caller` to demonstrate caller-scoped
  gates. Not useful on its own.
---

# nest-demo-child

One stage. Produces `output/child-evidence.md`, then a `publish` is allowed
(gated on that evidence existing). Exists to be invoked by `kakkoidev/nest-demo`
as a child run, so the runtime's caller-scoping can be exercised end to end.

## Reference
- `stages/01-produce.md` - the single stage and its publish gate.
- The end-to-end nesting behavior is tested by `kakkoidev/nest-demo`'s
  `eval/nesting.test.sh`.
