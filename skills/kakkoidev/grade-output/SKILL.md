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

This skill grades a run that has already completed, so the graded run has no
active stage and its gates are dormant during grading. More generally, the
runtime is caller-scoped: when a parent run invokes a child via `--caller`, the
parent's gates are suspended while the child run is open (the child is doing the
work) and resume when the child closes - so a parent's blocking gate will not
deny a child's legitimate tool call. Tamper-evidence still applies to the
suspended parent.

## Reference

- `stages/01-grade.md` - the vendored grading procedure and the `grading.json`
  schema (the frozen `## Outputs`).
- `eval/structure.test.sh` - proves the skill shape: the stage, the ICM-TOOLS
  declaration, and the declared grading.json output with `summary.pass_rate`.

This skill is a single staged grading run. Run its eval directly:
`cd <skill-dir> && sh eval/structure.test.sh`.
