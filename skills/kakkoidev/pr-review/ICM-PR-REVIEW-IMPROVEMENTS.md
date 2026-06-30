# pr-review skill - improvement plan

Status: proposal. Source: a live run of this skill on `meetsmore/meetsone` PR #24126
(SOBA-54, "auto-update zengin-code via dependabot + Soba Slack notify") on 2026-06-30,
plus a comparison against an independent human-run review of the same PR.

This document is the change spec. It records the failure that motivates each change,
the change itself (which file, what to add), how it is verified, and - explicitly -
the alternatives that were rejected and why, so they are not re-litigated.

---

## 0. The case study (why this exists)

The skill ran all 5 stages cleanly: deterministic gather, link-following (resolved the
SOBA-54 ticket + sibling test PR #24127), review, verification, sealed report. Gates,
telemetry, and seal all worked. The report was structurally complete and passed both
held-out checks.

It still missed the most important question about the PR.

The PR wires a Slack notification to fire when Dependabot opens a `zengin-code` bump PR,
via `on: pull_request: types: [labeled]` keyed on a `dependabot.yml`-declared label.

- **What the skill caught (correctly):** the Slack token is an Actions secret; on a
  Dependabot-context run only Dependabot secrets are available; the Dependabot store is
  empty -> `invalid_auth` (finding F1).
- **What the skill never asked:** does the `labeled` trigger even fire when Dependabot
  applies the label? The whole review was built on the unexamined assumption that the
  run starts. The verification stage degraded to "no runner: static coverage only" and
  stopped - it never ran `gh run list` and never looked at a real Dependabot PR.
- **What the independent human review did differently:** it pulled a real Dependabot PR
  (`#22118`), read its event timeline, saw Dependabot applies labels as discrete
  timestamped operations, and reasoned the trigger probably *does* fire (so F1 is the
  real blocker). It also carried a CONFIRMED/PLAUSIBLE/REFUTED status per finding and
  walked back its own overstatements when live evidence contradicted them.

### Root-cause diagnosis (3 weaknesses, one through-line)

The skill's README says it fixed the ported review agent's two weaknesses: silent/optional
context, and links that were never followed. This run exposed the **third**:

> **Verification is code-test-shaped and silently degrades to "static only" on the PRs
> where execution evidence matters most - CI / workflow / IaC / config / integration.**

Three concrete weaknesses feed it:

1. **No runtime grounding.** Nothing makes the review look at how the changed mechanism
   *actually executes* - run history, a real instance of the triggering actor/event. The
   single highest-leverage move (`gh api .../issues/22118/timeline`) is absent from the skill.
2. **No execution-chain trace for mechanism-type ACs.** Stage 03's traceability text is
   excellent but aimed at gating *sets/constants* (tax codes, regex, limits). AC-C here was
   a *mechanism* ("Slack notification sent on PR open"); there is no lens for "trace trigger
   -> condition -> step -> external effect for the real actor."
3. **CONFIRMED vs assumed is not tracked.** The report asserted F1 as the blocker while the
   load-bearing assumption beneath it (the run fires) was never executed. The report contract
   checks structure, not whether the primary claim was grounded in execution.

---

## 1. Design decision (read before implementing)

Two tempting directions were considered and **rejected**:

### Rejected A - split the review by concern into many sequential stages (logic, architecture, security, perf, ...)
- **Does not fix the failure.** The miss was grounding, not breadth. A "logic" stage and an
  "architecture" stage both still reason from the diff + assumptions; all of them miss "does
  it fire" unless something forces them to look at a real actor instance.
- **Kills synthesis - the best output of this run.** The most valuable finding was the
  *connection*: the feature's only production trigger is the exact path that fails, and the
  author's test masks it. One mind held trigger + secret + test-gap together. Siloed
  concern-stages run by isolated agents never assemble the connected finding. The skill
  already instructs "Synthesize before finishing - the connected finding is usually the most
  important"; concern-splitting fights it.
- **Seam bugs escape fixed buckets.** The trigger bug belongs to no single concern (config +
  Actions-runtime + actor-semantics at the seam). Category checklists create false confidence
  while the cross-cutting bug falls through.
- **Sequential stages accumulate context debt** - late stages reason with more pollution, not
  less, so "done properly per stage" gets worse, not better.

### Rejected B - add more prose to stage 03
- Stage 03's CONTEXT is already very dense and the trigger question was still missed. The
  "verify before flagging / before clearing" principle already existed and was simply not
  applied to the load-bearing assumption. More paragraphs get skimmed the same way.

### Accepted - decompose by *grounding activity*, keep judgment holistic, make verify mandatory
- Add a **runtime-evidence** grounding step *before* review.
- Keep the review **judgment holistic** (one pass, or parallel full-diff lanes with a union
  barrier - never sharded by topic) so cross-cutting synthesis survives.
- Make the **adversarial per-finding verify** mandatory (it is currently optional). The
  second pass is what makes a finding "done properly," not slicing the first pass by concern.
- Encode the high-leverage items as **deterministic tools, gates, and held-out checks** -
  the skill's own determinism philosophy - not as more prose.

> Note for icm-improve: icm-improve may only edit stage *prose*; gates, tools, the rubric,
> and held-out checks are frozen and human-gated. Every change below marked **[structural]**
> is a human-gated change to a tool / gate / eval; changes marked **[prose]** are stage-text
> edits icm-improve can later tune.

---

## 2. Changes, ranked by leverage

### C0 - [structural] Capture the diff in the deterministic gather
- **Gap:** `tools/gather-pr` captures file paths, counts, action feed, links - but NOT the
  diff content. The diff (the actual thing under review) is fetched ad-hoc in stage 03 via
  `gh pr diff`, so it is neither sealed nor reproducible.
- **Change:** in `tools/gather-pr`, also write `output/pr.diff` from
  `gh pr diff "$PR" --repo "$OR"`. Add it to the 01-context `## Outputs`.
- **Verify:** structure eval asserts `01-context/output/pr.diff` exists and is non-empty.

### C1 - [structural] New deterministic tool: `tools/gather-runtime-evidence`
- **Gap:** nothing gathers how the changed mechanism actually executes. This is the single
  change that would have caught PR #24126.
- **Change:** add `tools/gather-runtime-evidence <owner/repo> <pr#> <out-dir>` (gh + jq,
  read-only, deterministic). For each changed workflow / config file it:
  - lists the affected workflow(s) and their **run history**:
    `gh api repos/<OR>/actions/workflows`, then `gh run list --workflow <file> --json ...`;
  - records, for each run, the **triggering actor and event** (human vs bot, opened vs labeled);
  - pulls **a real historical instance of every actor/event the diff is conditional on** -
    e.g. when the diff references `dependabot`, fetch a recent Dependabot PR timeline
    (`gh pr list --author app/dependabot`; `gh api .../issues/<n>/timeline`) and emit the
    label/assign/review operations with actors + timestamps;
  - for any `secrets.*` referenced in a Dependabot/PR-target context, records the
    repo Actions vs Dependabot secret stores
    (`gh api .../actions/secrets`, `gh api .../dependabot/secrets`).
  - Output: `output/runtime-evidence.md` (deterministic facts only, no judgment).
- **Generalizes beyond CI:** the same stage gathers a real instance for cron jobs, webhooks,
  feature-flag gates, environment-conditional code - any behavior conditional on a runtime
  actor/event/environment.
- **Verify:** new stage gates on this artifact for config/workflow/infra/integration buckets
  (see C2, C4).

### C2 - [structural + prose] Stage 04: kill the "static only" escape hatch for non-code PRs
- **Gap:** stage 04's process is "Detect runner -> Suite -> Mutation"; with no test runner it
  writes `no runner: static coverage only` and stops. PR #24126 (3 config files) lived exactly
  there. "Execution-backed verification" became static reads.
- **Change (stages/04-verify.md):** add an explicit branch -
  > If the diff is CI / workflow / IaC / config / integration (no test oracle),
  > "execution-backed" means: workflow run-history + a real-actor/event instance
  > (from `runtime-evidence.md`) + event/security-context analysis. A report MUST NOT
  > be marked verified for such a PR on static reads alone.
- **Change (gate):** add an ICM-GATE so stage 04 (or its successor) cannot write its output
  for a config/workflow bucket unless `runtime-evidence.md` exists and is non-empty.

### C3 - [structural] Held-out check: the primary finding must carry execution evidence
- **Gap:** `eval-heldout/report-contract.test.sh` checks the report has a verdict + 7-point
  + `VERIFIED: PASS`. A report passes while its top finding rests on an unexecuted assumption
  (this run did). Status was not tracked.
- **Change:** new `eval-heldout/execution-evidence.test.sh` (held out from the LLM grader):
  - the report MUST tag each CRITICAL/HIGH finding with a status of
    `CONFIRMED` / `PLAUSIBLE` / `REFUTED` (mirror the human review's Status column);
  - any `CONFIRMED` finding MUST include an execution-evidence token: a command that was run
    and its observed result, or a citation into `runtime-evidence.md` /
    `verification.md`. A `CONFIRMED` with no execution token fails the check.
  - require an explicit `UNVERIFIED: <why>` tag for any load-bearing claim that could not be
    executed (so an assumption can never silently read as confirmed).
- **Verify:** this is the regression net for the whole improvement (see section 5).

### C4 - [structural] New stage: `03-runtime-evidence` (grounding, before review)
- **Gap:** review currently runs straight off context+links, with no grounding pass.
- **Change:** insert a stage between 02-links and review:
  - runs `tools/gather-runtime-evidence` (C1);
  - then, model-mediated, produces a **per-AC execution-chain trace**: for each acceptance
    criterion that asserts an *effect/mechanism*, lay out trigger -> condition -> step ->
    external effect and mark each link `executes for the real actor` / `unverified` /
    `broken`, citing `runtime-evidence.md`.
  - Output: `output/runtime-evidence.md` + `output/ac-execution-trace.md`.
- **Why a stage, not prose:** it is a distinct grounding activity with its own deterministic
  tool and its own gate; making it a stage is the "do it properly" decomposition that the
  concern-split was reaching for, on the correct axis.

### C5 - [structural + prose] Mandatory adversarial per-finding verify
- **Gap:** stage 03's ensemble/adversarial mode is "optional, for high-stakes PRs," with no
  trigger. A single pass missed the trigger question.
- **Change:** make the verify stage produce, per finding, an independent adversarial pass that
  tries to **refute** it, ending in `CONFIRMED` / `PLAUSIBLE` / `REFUTED` + the evidence. For
  HIGH-stakes diffs (see L3) run perspective-diverse verifiers (correctness / security /
  does-it-actually-execute) rather than one. The find phase stays holistic; verify is the
  per-finding second pass.

### L1 - [prose] Prior reviews, approvals, and "manually tested" claims are hypotheses
- **Gap:** the skill treats the ticket as a hypothesis but is silent on prior reviews. This
  run absorbed a prior bot review's "fires too broadly" frame and never questioned "fires at
  all." An existing approval was a lull signal.
- **Change (stages/03 or review stage):**
  > Prior bot/human review comments, and approvals, are hypotheses - re-derive, do not inherit
  > their framing (a prior reviewer inverted the trigger question on this PR). An author's
  > "manually tested" claim is a hypothesis: identify which variables the test held constant
  > (actor, event, environment) versus the real production path, and whether the test could
  > pass while the feature is broken. A test that passes regardless of whether the feature
  > works has zero diagnostic power.

### L2 - [prose] Runtime-context checklist in the config/integration lens
- **Gap:** the config lens covers secrets / permissions / untrusted-input (it caught F1, the
  actor-guard, and title-injection) but nothing on *triggering / execution semantics*.
- **Change (stages/03 config lens):** add a checklist -
  - does the trigger actually fire for the intended actor/event? (bot vs human; create-time
    vs post-create label; `pull_request` vs `pull_request_target`)
  - GITHUB_TOKEN recursion: events from a workflow's GITHUB_TOKEN do not start new runs;
  - Dependabot/automation context: read-only token, secrets sourced from the Dependabot store
    only, not Actions secrets;
  - generalize: for cron/webhook/flag/env-conditional code, what is the real trigger context
    and does the gate match it?

### L3 - [prose] Mandatory-ensemble decision rule
- **Change (stages/03):** ensemble + perspective-diverse verify is **mandatory** (not optional)
  when the diff touches auth / secrets / CI-triggers / payment / migrations, or when behavior
  is conditional on actor / event / environment. Single pass is fine only for routine diffs.

---

## 3. Proposed pipeline (vs current)

| # | Current | Proposed | Change |
|---|---------|----------|--------|
| 01 | context (summary + feed + links) | context (+ **diff**) | C0 |
| 02 | links (depth-2) | links (depth-2) | unchanged |
| 03 | review (everything) | **runtime-evidence** (run history + real actor/event + per-AC execution trace) | C1, C4 |
| 04 | verify (suite + mutation) | **review** (holistic judgment; findings tagged CONFIRMED/PLAUSIBLE referencing runtime evidence) | C2 lens, L1, L2, L3 |
| 05 | report (assemble + seal) | **verify** (mandatory adversarial per-finding; mutation where a code oracle exists; non-code => run-history/real-actor) | C5, C2 gate |
| 06 | - | **synthesize + report** (connect findings, seal) | keeps the synthesis instruction explicit |

Judgment (review) stays a single holistic stage. The decomposition is grounding-before and
verify-after, not topic-sharding.

---

## 4. What NOT to do

- Do **not** split review into sequential concern-stages (logic / arch / security). It does
  not fix grounding, it destroys synthesis, and seam bugs escape the buckets. (Section 1, Rejected A.)
- Do **not** answer this by adding more prose to an already-dense stage. Prefer tools/gates/evals. (Section 1, Rejected B.)
- Do not assume any failure here was purely the skill's. One failure in the run (an
  overconfident "WILL NOT FIRE" reversal) happened *off-pipeline*, in an ad-hoc step taken
  outside the skill. The skill cannot be blamed for steps taken outside it - but C1 (the
  real-actor tool) would have grounded even that ad-hoc step.

---

## 5. Acceptance / regression fixture

Use PR #24126 as the fixture for these improvements. The improved skill, run cold on it, must:

1. Produce `runtime-evidence.md` that cites a **real Dependabot PR** (e.g. #22118) and its
   label-application timeline (discrete, by `dependabot[bot]`) - not only the notify
   workflow's own empty run history.
2. Produce an `ac-execution-trace.md` that, for AC-C ("Slack notification on PR open"),
   traces trigger -> label condition -> checkout/post step -> Slack effect, and flags the
   `labeled`-fires question and the Dependabot-secret-context question as explicit links to verify.
3. In the report, tag the token finding `CONFIRMED` **with an execution token** (the
   `dependabot/secrets` query + result) and must NOT assert the trigger behavior without a
   `runtime-evidence` citation or an `UNVERIFIED:` tag.
4. Pass `eval-heldout/execution-evidence.test.sh` (C3).

Fails-on-revert: with the current skill (no runtime-evidence stage, "static only" escape
hatch, no status/execution-token requirement), step 1 produces nothing, the trigger question
is never surfaced, and the report reads CONFIRMED without grounding - i.e. the exact 2026-06-30
failure.

---

## 6. Implementation order

1. C0 + C1 (tools) - cheap, deterministic, highest leverage.
2. C4 (new runtime-evidence stage wiring + gate) and C2 (stage-04 branch + gate).
3. C3 (held-out execution-evidence check) - locks the gain so icm-improve cannot regress it.
4. C5 (mandatory verify) and renumber stages.
5. L1, L2, L3 (prose lenses) - a single reviewed pass; let icm-improve tune wording after.
