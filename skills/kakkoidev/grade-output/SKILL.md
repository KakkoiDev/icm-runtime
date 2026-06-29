---
name: grade-output
description: >
  Grade a completed run's output files against a frozen `## Outputs` rubric and
  emit a structured grading.json, run as an ICM skill so the grading step is
  observable: its tokens/model land in the telemetry index, its verdict (with
  inline evidence) is sealed and tamper-evident, and a `--caller` link records
  which run it graded. This is the skill-creator grader procedure vendored
  in-repo (pinned, no external plugin dependency) - the judgment is still an LLM
  call, so there is no deterministic gate; what the runtime adds here is
  observability, not verification of correctness. Used by icm-improve, and
  standalone to grade any run. Triggers: "grade this output", "score against the
  rubric", "grade-output".
---

# grade-output

The skill-creator grader, vendored as an ICM skill. It judges whether a run's
produced outputs satisfy each declared expectation, citing evidence, and writes
a `grading.json` verdict.

## Why this is an ICM skill (and what it does NOT buy)

Grading is an LLM judgment. A deterministic gate cannot verify a verdict is
*correct* - so this skill has no blocking `ICM-GATE`, and pretending otherwise
would be theater. What running it under the runtime *does* buy:

- **Telemetry**: the grading step's model + tokens land in `skill-runs.jsonl`
  instead of vanishing into the caller's session.
- **Seal**: `grading.json` is sealed and tamper-evident. Because the grader
  quotes its evidence inline (per the schema), the verdict and the evidence it
  rests on are sealed together.
- **Caller linkage**: invoke with `--caller <graded-ws>/<run_id>/<stage>` and
  `icm.sh children` shows which run this grading judged.
- **Pinned**: the grader procedure lives here, version-controlled, with no
  dependency on an external plugin that could change grading semantics silently.
- **Audit**: `ICM-TOOLS expect="(Read|Write)"` lets `icm.sh audit` catch a
  degenerate grader that wrote a verdict without reading any evidence.

## Invocation

```
icm.sh init kakkoidev/grade-output [--caller <graded-ws>/<run_id>/<stage>]
```

Then spawn the grader to execute stage `01-grade` against the run being graded
(its path given in the spawn prompt), run `icm.sh stage-done`, then `icm.sh seal`.

## Composition note

When a parent (e.g. icm-improve) invokes this, the graded run has already
completed before grading starts - the two runs do not overlap. ICM gates are
project-global across *open* runs (a parent's active-stage gate is evaluated
against every tool call while it is open), so sequential invocation is what keeps
a grading tool call from being denied by an unrelated open gate. Do not grade
from inside a parent stage that still has a blocking gate active.

## Reference

- `stages/01-grade.md` - the vendored grading procedure and the `grading.json`
  schema (the frozen `## Outputs`).
- `eval/structure.test.sh` - proves the skill shape: the stage, the ICM-TOOLS
  declaration, and the declared grading.json output with `summary.pass_rate`.

This skill is a single staged grading run. Run its eval directly:
`cd <skill-dir> && sh eval/structure.test.sh`.
