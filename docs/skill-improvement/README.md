# Skill improvement via reference-agent comparison

A repeatable method to drive an ICM skill to **parity-or-better** with the mature Claude Code agent it ports, with documented proof at every step. Designed to generalize to all skills (grade + improve them the same way).

Origin: improving `kakkoidev/pr-review` against the `review` agent (per-skill log: `pr-review.md`).

## The loop

1. **Inputs** - pick real, varied inputs. For `pr-review`: real PRs of different shapes (validation bug, large refactor, CI/automation, migration/data). Variety is essential - a fix found on one shape must be tested on another to prove it generalizes (not overfit).
2. **Run both** - run the skill AND the reference agent on each input, read-only. Save both outputs verbatim. The agent output is the **fixed baseline**; capture its findings durably (so later iterations re-run only the *skill* and diff against the saved baseline - cheaper, stable reference).
3. **Diff + classify** each finding into: `MATCH` (both), `SKILL-MISSED` (agent only), `SKILL-UNIQUE` (skill only), `SKILL-FALSE-POSITIVE` (skill flagged, collapses on inspection), `SHALLOWER` (skill found but agent connected/went deeper). **Verify contested findings against source before crediting either side** (scars #7 - findings are hypotheses).
4. **Extract gap-classes** - generalize the misses / false-positives / shallower into reusable classes (not input-specific).
5. **Encode** - edit ONLY stage prose / `## Outputs` to address a gap-class. Generalizable + scars-aligned, NOT overfit (omit on-the-nose examples that name the specific answer). Prose-only: never touch gates/checks/tools/the rubric structure (the icm-improve guard discipline).
6. **Re-verify** - re-run the skill on the input(s) where the gap appeared, **blind** (the executor sub-agent is not told the answer), diff against the saved baseline; confirm the gap closes and nothing regresses. A blind catch is the honest proof.
7. **Log** - record the run, findings, classification, the gap-class, the exact edit + rationale, and before/after, in the per-skill log. Commit. This is the "proof" deliverable.

## Grading (per input, then aggregate)

For each input, score the skill against the saved agent baseline:
- `matches` = agent-real findings the skill also caught
- `misses` = agent-real findings the skill lacked
- `unique_real` = skill findings the agent lacked, verified real
- `false_positives` = skill findings that collapse on inspection
- `depth` = of matched findings, how many the skill connected/grounded as well as the agent

A skill is **"as good or better"** across the input set when: `misses == 0`, `false_positives == 0`, and `unique_real >= 0` (with depth comparable). Track the trend per iteration.

## Guardrails

- **Findings are hypotheses** (scars #7): verify against source before crediting the skill OR the agent. Contested findings are flagged, not scored, until verified.
- **Don't overfit**: a fix must generalize across shapes; validate it on a different shape than it was found on.
- **Prose-only edits**: never weaken a gate/rubric to "pass". Improvements are to instruction prose + `## Outputs` expectations only.
- **Reference is fixed**: re-run the skill each iteration, not the agent. Re-baseline the agent only if the agent itself changes.
- **Infra**: spawn sub-agents UNNAMED (the `name:` teammate path is broken in this env - see TASK.md infra note). Read-only on the target repo (no worktree mutation; use `gh pr diff`).

## Why not autonomous icm-improve

`icm-improve` optimizes stage prose against an LLM grader scoring `## Outputs`. The high-value gaps here came from **comparing against the agent + verifying against source**, not from grading output vs a rubric - so autonomous icm-improve does not find them. This comparison loop is the engine; icm-improve is a complement only once `## Outputs` encodes the dimension.
