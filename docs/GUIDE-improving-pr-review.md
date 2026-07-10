# Guide: improving pr-review (make it compound, not thrash)

Status: LIVING GUIDE, started 2026-07-09. How to keep the pr-review skill getting
better without over-fitting to the last miss or drowning it in prose. Written after
a run of reactive fixes (checklist audit, changed-value dual, value-binding FP,
same-PR independence) exposed that "add a rule for the last miss" is not the same as
"the skill got better."

## 1. The loop

```
run on a real PR  ->  a miss surfaces  ->  CLASSIFY the miss by layer  ->  fix at that layer  ->  FREEZE it (fixture / contract / scar)  ->  re-run, confirm
```

The freeze step is what makes it compound. Without it, the next refactor silently
undoes the fix and the miss returns. A fix that is not frozen is a rumor.

## 2. Classify the miss by layer BEFORE fixing

Fixing at the wrong layer is wasted effort (a judgment problem does not yield to a
gate; an enforcement problem does not yield to a scar). Three layers:

| Layer | The miss is... | Fix with | Can it be made deterministic? |
|-------|----------------|----------|-------------------------------|
| **Enforcement** | a check that should run never ran (checklist audit was missing) | a deterministic artifact the stage MUST produce + a gate/held-out contract that fails if absent | YES - this is the strong layer |
| **Judgment** | a check ran but the verdict was wrong/lazy (audit graded by checkability) | prose discipline + a scar lens + exercise-in-verify + adversarial/ensemble | NO - model-mediated, permanently probabilistic |
| **Contract** | the run broke its own guarantee (reviewed the working tree, not the sealed diff) | a determinism guard / a held-out contract check | YES |

Rule: push every miss down to the lowest layer that can hold it. A judgment miss you
can convert into an enforcement miss (make the check produce a required artifact) is
a win; one you cannot is a scar + an adversarial pass, and you accept the residue.

## 3. Freeze every miss as a ratchet

Two freeze mechanisms, both already in the repo:

- **`eval/` - deterministic tool tests + fixtures.** A frozen input + expected
  output, run offline, no model. Use for anything a tool computes (link extraction,
  checklist extraction, impact sweep, prior-run detection). Each past tool miss
  becomes a fixture; a change that regresses it fails `icm.sh eval`.
- **`eval-heldout/` - output-contract floor.** Asserts the REPORT has the required
  shape (verdict, 7-point, checklist-audit section when a checklist exists, bias-alarm
  line, Independence line on a re-review). Held out from the LLM grader so icm-improve
  cannot game it. Use for "the review must ADDRESS X", never "the review judged X
  correctly" (that is not checkable).

What is freezable and what is not:

- **Mechanical extraction / structure** -> freeze in `eval/` (deterministic).
- **"the section exists / the disclosure is present"** -> freeze in `eval-heldout/`.
- **"the judgment was right"** (did it catch THIS false positive, grade to a uniform
  bar, not inherit a predecessor) -> NOT freezable. Covered by `references/scars.md`
  (a lens) + the adversarial/ensemble layer. Do not pretend a held-out check proves
  quality; it proves presence.

## 4. Current miss corpus (the seed - grow this)

| Miss (real, dated) | Layer | Frozen by |
|--------------------|-------|-----------|
| PR-template checklist never audited (#24370) | enforcement | `01` extracts `checklist.tsv` (tool) + `eval-heldout/report-contract` asserts the audit section + bias-alarm line |
| Checklist graded by checkability, not a uniform bar (#24370) | judgment | scar 37 + `04` uniform-bar prose + `05` exercise-asserted |
| Changed-value break an existing test - dead-code's dual (#24198) | enforcement | `tools/gather-impact` + `eval/changed-literal-impact.test.sh` |
| Value-binding false positives: nested sub-bullet + blank-line widening (#24370, the reviewed repo) | (belongs to the reviewed codebase, not the skill) | the meetsone repo's own spec; the skill lesson is the review-detection one below |
| Same-PR re-review inherited its predecessor (#24370) | contract | `01` writes `prior-runs.tsv` + `04` blind-pass rule + `06` Independence line + `eval-heldout` assertion |
| Reviewed the working tree / unpushed commit, not the sealed diff (#24370) | contract | (OPEN) needs an out-of-seal guard - see section 7 |

When a new miss lands, add a row and its freeze. An empty "frozen by" cell is a
TODO, not a closed miss.

## 5. Proactive miss-finding (recommended, model-mediated)

Every miss above was found by a human or a second model, not by the skill. That does
not scale and over-fits to whoever looked. Add a **completeness-critic** pass: after
the review, a red-team step whose only job is "what did this review MISS against the
diff - a bucket not dispatched, a claim unverified, a value removed, a guard not
falsified?" Its output becomes the next fixture. This is model-mediated (section 2,
judgment layer), so it lowers the miss rate, it does not floor it. Keep it OUT of the
deterministic evals; it is a capability, not a contract.

## 6. Measure the miss rate, or you are guessing

"Improvement" = the miss rate on NEW PRs drops. The only way to know is to log, per
reviewed PR, what the skill found vs what a reviewer later found, and watch the
number. Per-run telemetry is already sealed; add the found-vs-later-found delta.
Without measurement you cannot distinguish a real improvement from prose that made
the contract longer.

## 7. Anti-patterns (name them, avoid them)

- **Prose accretion.** Every reactive fix wants to add a "MANDATORY" paragraph to a
  stage. `04` is already the largest stage. Beyond a point, more prose CAUSES the
  forgetting it is meant to prevent (the model drops one of twelve emphatic rules).
  Discipline: prefer demoting an enforceable rule to a tool + a held-out contract over
  adding a paragraph; periodically cut stage prose and move checks into `checks/` +
  `eval-heldout/`. See `PROPOSAL-check-registry-completeness.md` for the general form.
- **Fixing at the wrong layer** (section 2): a scar for an enforcement gap, a gate for
  a judgment gap.
- **Over-fitting to n=1.** One miss is an anecdote. Fix it, but do not re-architect
  the pipeline around it; wait for the pattern (2-3 misses of a kind) before a
  structural change.
- **The improver gaming its own grader.** icm-improve edits only stage prose, grades
  against a frozen rubric, and a held-out deterministic check runs independently of
  the LLM grader; promotion to canonical is human-gated. Keep all four properties.

## 8. Where things live

- `stages/*.md` - the contracts (frozen into each run by `cmd_init`).
- `tools/` - deterministic extractors (`gather-pr`, `gather-impact`,
  `gather-runtime-evidence`, `extract-checklist`, `fetch-web`).
- `eval/` - deterministic tool tests + fixtures (`icm.sh eval`).
- `eval-heldout/` - output-contract floor for icm-improve.
- `references/scars.md` - the judgment-layer lens, frozen per run.
- `PROPOSAL-check-registry-completeness.md` - the general enforcement machinery for
  when the number of checks grows past what prose can hold.
- icm-improve (separate skill) - the automated run/grade/edit loop over stage prose.
