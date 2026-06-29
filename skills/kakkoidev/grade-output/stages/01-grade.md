# Stage 01: Grade outputs against the rubric

<!-- ICM-TOOLS expect="(Read|Write)" -->

Evaluate each expectation against the produced outputs (and a transcript, if
provided), determine pass/fail with cited evidence, and write a `grading.json`
verdict. You have two jobs: grade the outputs, and critique the expectations
themselves - a passing grade on a trivially-satisfied assertion creates false
confidence, so flag it.

There is no blocking gate on this stage: the verdict is an LLM judgment, not a
deterministic check. `ICM-TOOLS expect="(Read|Write)"` lets the audit confirm you
actually read evidence before writing a verdict.

## Inputs

The run to grade is named in your spawn prompt (and recorded as this run's
`--caller`). For an ICM run at `<graded-run>`:

| Source | Location | Scope |
|--------|----------|-------|
| Expectations | each graded stage's `<graded-run>/<stage>/CONTEXT.md` `## Outputs` section | one expectation per declared artifact/property |
| Outputs | each graded stage's `<graded-run>/<stage>/output/` | the artifacts to judge |
| Transcript | optional, path given in the prompt | execution steps, if available |

## Process

1. **Read the expectations.** From each graded stage's `## Outputs`, derive the
   concrete expectations (each declared artifact and the properties stated for it).
2. **Examine the outputs.** List and read every file under each `output/` dir.
   Note contents, structure, and quality. Do not rely on a transcript's claim of
   what was produced - read the files.
3. **Evaluate each expectation.** For each: search the outputs (and transcript)
   for evidence, then decide:
   - **PASS**: clear evidence the expectation holds AND the evidence reflects
     genuine completion, not surface compliance (correct filename AND correct
     content).
   - **FAIL**: no evidence, contradicting evidence, or superficial evidence (right
     shape, wrong/empty substance). When uncertain, the burden of proof is on the
     expectation - default to FAIL.
   Cite the specific text supporting each verdict. No partial credit.
4. **Extract and verify claims.** Pull implicit claims from the outputs (factual,
   process, quality) and verify each against the outputs/transcript. Flag any that
   cannot be verified. This catches issues the declared expectations miss.
5. **Critique the expectations.** Only where there is a clear gap, suggest: an
   assertion that passed but would also pass a clearly-wrong output; an important
   observed outcome no assertion covers; an assertion not verifiable from the
   outputs. Keep the bar high - flag what the author would call a good catch.
6. **Write the verdict** to `output/grading.json` in the schema below.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/grade-output \
  --stage 01-grade
```

## Outputs

| Artifact | Location | Format |
|----------|----------|--------|
| Grading verdict | output/grading.json | JSON per the schema below; `summary.pass_rate` in [0.0, 1.0] |

```json
{
  "expectations": [
    { "text": "<the expectation>", "passed": true, "evidence": "<quote or description>" }
  ],
  "summary": { "passed": 2, "failed": 1, "total": 3, "pass_rate": 0.67 },
  "claims": [
    { "claim": "<extracted claim>", "type": "factual|process|quality", "verified": false, "evidence": "<...>" }
  ],
  "eval_feedback": {
    "suggestions": [ { "assertion": "<optional>", "reason": "<why this assertion is weak / what is uncovered>" } ],
    "overall": "<brief assessment, or 'No suggestions, expectations look solid'>"
  }
}
```

Field rules:
- `expectations[].passed` is a boolean; `evidence` is a specific quote or
  description, never empty.
- `summary`: `passed + failed == total`; `pass_rate == passed / total` (1.0 when
  `total` is 0).
- `claims` and `eval_feedback` are required keys; use `[]` / a short `overall`
  when there is nothing to report.
