# Proposal: check-registry completeness (no check silently dropped as checks grow)

Status: PROPOSAL 2026-07-09. Not implemented. Motivated by the pr-review checklist
miss (SOBA-285 / PR #24370): the review never audited the PR against its template's
mandatory checklist, and when it later did, it graded items by how easy each was to
scan rather than to a uniform bar (skill scars.md #37). This proposes a general
mechanism so that adding the Nth check to any ICM skill cannot make the (N-1)th get
forgotten.

## 1. Problem

ICM stage contracts list their checks as **prose** ("dispatch every specialist",
"audit every checklist item", "run the dead-code dual"). Prose does not bind. As a
stage accretes checks, the model reads a longer contract and probabilistically drops
one - and the drop is **silent**: the run completes, seals, and reads as thorough.
This already happened twice on one PR:

- 04-review's contract names ~10 sub-checks; the PR-template checklist audit was not
  among them, so it never ran until a human asked.
- When it did run (ad-hoc), the audit graded the mechanically-scannable items hard
  (JSDoc, secrets, deps) and gave the judgment items (coverage-for-risk, docs
  sufficiency, observability) a faith pass - so the single surfaced gap landed on the
  item the human had named. Anchoring dressed as thoroughness.

The existing `PLAN-gate-enforcement.md` mechanism (ICM-GATE + PreToolUse hook) makes a
**single named** gate binding. It does not make **completeness over a growing set** of
checks binding: there is nothing that says "every check that SHOULD have run, ran."

Two failure modes, only the first of which this proposal solves:

- **Omission** (a check was skipped). Solvable deterministically. This proposal.
- **Bad judgment** (a check ran but the verdict was wrong/lazy). Not deterministically
  solvable; stays model-mediated (verified/asserted tagging + exercise-in-verify + bias
  alarm). Named here only to bound the claim.

## 2. Goal / non-goals

Goal: adding a check is adding a row to a data file; the harness then guarantees the
check is enumerated when applicable and that the run produced an answer for it, whatever
N is.

Non-goals (state them so the design is not oversold):

- **Presence != correctness.** The completeness gate proves a check was *addressed* (a
  row exists, evidence is non-blank), never that the judgment was *right*.
- **No new stages.** Completeness is a registry + one enumerate tool + one manifest + one
  gate checker, riding the gate primitive that already exists. Stage count stays flat as
  check count grows (the whole point).
- **Applicability is tool-computed where possible.** If the model decides which checks
  apply, it under-scopes (marks things N/A to shrink the list). Determinism moves that
  decision off the model.

## 3. Design principle: move the guarantee off the model

The model cannot be instructed into not-forgetting; a bigger "MANDATORY" list is more to
drop, not less. So the list stops living in the model's head:

```
enumerate (deterministic)  ->  require (one manifest row per enumerated id)  ->  verify (deterministic gate)
```

The model is *handed* the filtered set of applicable checks and must return one row each.
It never holds the full registry. The guarantee lives in the enumeration (a tool) and the
gate (a checker) - both deterministic, both O(1) to maintain as N grows.

## 4. Design

### 4.1 Check registry - data, not prose

Per skill: `checks/registry.tsv`. One row per check. Frozen into the run by `cmd_init`
alongside the other `checks/*` (the runtime already copies `checks/` into the run root and
sha256s it in `.manifest`, so the registry is tamper-evident for free).

Columns (TAB-separated; `#` comment lines and blanks ignored):

```
id              applies_when              produces          method     signal_tool
jsdoc           prod_ts_files             manifest_row      mechanical gather-doc-coverage
secrets         always                    manifest_row      mechanical gather-secrets
deps            manifest_changed          manifest_row      mechanical gather-dep-diff
coverage-risk   prod_files                manifest_row      judgment   -
docs-sufficient docs_files                manifest_row      judgment   -
observability   prod_files                manifest_row      judgment   -
rbac            touches_endpoints         manifest_row      judgment   -
checklist       checklist_nonempty        checklist-audit.md contract  gather-pr
dead-code       always                    manifest_row      judgment   -
external-rule   has_gating_constant       manifest_row      judgment   -
specialist:owasp security_relevant_files  manifest_row      judgment   -
```

- `applies_when`: a named predicate evaluated by the enumerate tool (4.2), NOT free text.
- `produces`: the artifact that satisfies the check - either a row in the coverage
  manifest, or a named file (e.g. the checklist audit already writes its own file).
- `method`: `mechanical` (a `signal_tool` computes a raw signal, auto-fills the row),
  `judgment` (model must fill + tag verified/asserted), or `contract` (satisfied by a
  file the eval-heldout already asserts).
- `signal_tool`: the deterministic tool that feeds a mechanical check (4.4), or `-`.

Registries compose: the runtime could ship a `checks/registry.core.tsv` (dimensions common
to all reviews) that a skill's own `registry.tsv` extends.

### 4.2 Applicability enumeration - `tools/enumerate-checks`

Deterministic. Inputs: the frozen `registry.tsv`, the sealed `pr.diff`, `pr-context.md`
buckets, `checklist.tsv`. For each row, evaluate `applies_when` mechanically:

```
prod_ts_files          -> pr-context buckets show a prod *.ts file
manifest_changed       -> diff touches package.json / *.lock / Cargo.toml / ...
touches_endpoints      -> diff touches a controller/route/handler path or decorator
checklist_nonempty     -> checklist.tsv non-empty
security_relevant_files-> diff touches auth/crypto/input/sql/user-data paths
has_gating_constant    -> diff adds a hardcoded set/list/rate/regex/limit/date
always                 -> true
```

Writes `output/applicable-checks.tsv`: `id <TAB> applies=yes|no <TAB> reason`. `no` rows
carry the diff-grounded reason they do not apply (so an N/A is auditable, not asserted).
A predicate the tool cannot decide mechanically emits `applies=unknown` -> treated as
`yes` (fail toward doing the check, never toward skipping it).

### 4.3 Coverage manifest - the model-filled artifact

The review stage writes `output/coverage.tsv`, one row per `applies=yes` id:

```
id              verdict   method      evidence
jsdoc           GAP       verified    gather-doc-coverage: 3/15 changed fns lack a doc block (isPlaceholder, levenshtein, main)
coverage-risk   MET       verified    exercised in 05: checkLabeledSchemaRefs branches - blank-line, table-row, full-width-colon all have a test; measured, not counted
docs-sufficient GAP       verified    read CONTRIBUTING.md +N: the label-convention block omits the loose-list rule a newcomer needs
rbac            N-A       verified    applicable-checks.tsv: no endpoints in diff (CLI script)
secrets         MET       verified    gather-secrets: 0 hits
```

- `verdict`: `MET` / `GAP` / `N-A`. A `GAP` becomes a finding at its severity.
- `method`: `verified` (a check/tool ran or the claim was exercised) or `asserted`
  (judgment, provisional -> handed to 05 to exercise; a row still `asserted` after 05 is a
  gate failure - see 4.5).
- `evidence`: non-blank, and for `mechanical` rows it is the `signal_tool` output verbatim.

Mechanical rows are pre-filled by the signal tools (4.4); the model may only *interpret*
the signal into a verdict, never overwrite the raw signal. Judgment rows the model fills.

### 4.4 Mechanical signal tools - signals, not verdicts

Small deterministic tools, each feeding one mechanical registry row. Examples:

- `gather-doc-coverage <diff>` -> per changed function, doc-block present? (the awk scan a
  human did by hand on #24370, frozen).
- `gather-secrets <diff>` -> secret-pattern grep hits on added lines.
- `gather-dep-diff <diff>` -> added/changed deps + whether the PR text matches.

Each emits a labelled **signal**, mirroring `gather-impact`'s existing discipline
("candidate to verify, never confirmed break"): the header of every signal file reads
`RAW SIGNAL - not a verdict; interpret, do not trust`. This is what makes the
mechanical/judgment split *structural*: the tool did the scanning and says so, so the model
cannot bank a scan as a judgment. It must still judge the judgment rows itself. Growing the
mechanical set is cheap and removes easy items from the model's plate; it never removes the
obligation to judge the hard ones.

Risk: a mechanical tool has false negatives (empty JSDoc block reads "present"; a secret
regex misses a base64 token). Because the tool emits a signal not a verdict, the model is
still on the hook to sanity-check it - and the tool must fail toward flagging (a doubtful
line is a hit), never toward clearing.

### 4.5 Completeness gate - deterministic, on the existing primitive

A `checks/completeness.sh`, wired via the ICM-GATE line that already gates the review /
report stage's `Write`. It reads `applicable-checks.tsv` and `coverage.tsv` and DENIES
until:

1. every `applies=yes` id has a `coverage.tsv` row (missing row -> DENY, names the id);
2. every row's `evidence` is non-blank;
3. no row is still `method=asserted` after stage 05 (an unexercised judgment is not
   complete);
4. every `produces=<file>` check's file exists (e.g. `checklist-audit.md`).

Fail-closed and tamper-evident by reusing what `PLAN-gate-enforcement.md` already built:
the registry and checker are frozen + hashed in `.manifest` at `cmd_init`, so a mid-run
edit that drops a check from the registry is a tamper DENY, not a silent shrink.

This is the load-bearing guarantee. It is O(applicable-N) and needs no edit when a check is
added - the new row flows through enumerate -> manifest -> gate automatically.

### 4.6 Wiring into pr-review (the first consumer)

- `checks/registry.tsv`: seed from the review's existing dimensions (7-point rows,
  specialist dispatch, dead-code dual, external-rule, checklist audit) + the mechanical
  PR-template items.
- 01-context: run `enumerate-checks` after gather-pr -> `applicable-checks.tsv`; run the
  mechanical `signal_tool`s -> pre-filled signal files. (Deterministic, fits 01's ethos.)
- 04-review: fill `coverage.tsv` (one row per applicable id); the checklist audit and
  specialist dispatch become registry-enumerated, not prose-remembered.
- 05-verify: exercise every `asserted` row -> `verified` or `GAP` (already added for the
  checklist; generalizes to all judgment rows).
- 06-report: the report's `Write` is gated by `completeness.sh`; the report renders
  `coverage.tsv` as a table + the bias-alarm line.

The checklist fix already shipped is exactly this pattern hardcoded for one registry (the
PR template). This proposal lifts it to a general registry so every dimension gets the same
enumerate -> require -> verify treatment.

## 5. Enforcement flow (what fails when)

| Situation | Result |
|-----------|--------|
| Registry gains a row; predicate true; model omits its coverage row | 06 report `Write` DENIED: "completeness: missing coverage for `<id>`" |
| Model writes a row with blank evidence | DENIED: "`<id>` evidence empty" |
| Judgment row still `asserted` after 05 | DENIED: "`<id>` asserted but not exercised" |
| Check genuinely N/A | model writes `N-A` + the diff-grounded reason from `applicable-checks.tsv`; passes |
| Someone edits `registry.tsv` mid-run to drop a check | tamper DENY (sha256 manifest mismatch) |
| Mechanical signal tool missing/errors | signal file absent -> its row cannot be `verified` -> `UNVERIFIED` -> DENY (fail closed) |

## 6. Scaling property

The model is handed `applicable-checks.tsv` (already filtered) and returns a row per id.
It never enumerates from memory. The gate verifies the set mechanically. Therefore
completeness is independent of N: 10 checks or 100, the enumerate tool lists them and the
gate confirms each was answered. Adding a check touches one data file. This is the property
the request ("must not forget anything even as checks grow") actually needs, and it is
unattainable by any amount of contract prose.

## 7. Threat model / honest limits

Defends against a negligent model that drops a check, banks a scan as a judgment, or
under-scopes applicability. Does NOT defend against:

- **Wrong-but-present verdicts.** A row can say `MET verified` with plausible-but-hollow
  evidence. The gate checks non-blank, not truth. Mitigation is the weaker model-mediated
  layer: mechanical rows are tool-owned (the model cannot overwrite the raw signal),
  judgment rows are exercised in 05, and the bias alarm runs on the exercised set. Presence
  is guaranteed; quality is only pressured.
- **Fabricated evidence text** on a judgment row. Same residual as the existing gate design
  (the checker verifies artifact consistency, not capture truth). Mechanical rows are
  immune (tool-owned); judgment rows are the exposure.
- **A predicate the tool mis-decides.** Mitigated by `unknown -> yes` (never skip on doubt)
  and by the N/A reason being diff-grounded and auditable.

The claim is bounded: this makes *silent omission* structurally impossible, which is the
failure that started this. It does not make the review *correct*.

## 8. Implementation order

1. `tools/enumerate-checks` + a first `registry.tsv` for pr-review (predicates for the
   applicability set in 4.2).
2. `checks/completeness.sh` + wire its ICM-GATE onto 06-report's `Write` (reuse the frozen
   + hashed `checks/` path the runtime already has).
3. One mechanical signal tool end-to-end (`gather-doc-coverage`) to prove the
   signal-not-verdict pattern; add the rest incrementally.
4. Move 04/05/06 prose to consume `coverage.tsv`; keep the prose as guidance, not as the
   completeness source.
5. eval-heldout: assert `coverage.tsv` covers `applicable-checks.tsv`, and that mechanical
   rows carry the raw signal verbatim.
6. Tests (section 9) written WITH 1-5.

## 9. Tests (each fails on revert)

`tests/completeness.test.sh`, tmp-dir, no network:

1. Registry with 3 applicable checks, coverage covers 2 -> gate DENY names the third.
2. All covered, one row blank evidence -> DENY.
3. All covered + evidence, one row `asserted` post-05 -> DENY.
4. All covered, exercised, evidence present -> PASS.
5. `applies_when` false for a check (predicate grounded in a fixture diff) -> that id not
   required; absent from coverage is fine.
6. Registry edited after init (drop a row) -> tamper DENY.
7. Mechanical row: model overwrites the raw signal -> eval-heldout catches the mismatch.
8. `enumerate-checks` on the #24370 fixture diff lists `checklist`, `jsdoc`, `coverage-risk`
   as applicable and `rbac` as N/A with reason.

## 10. Migration

- The shipped checklist audit becomes registry row `checklist` (produces
  `checklist-audit.md`, method `contract`) - already enforced by
  `eval-heldout/report-contract.test.sh`; fold that assertion into `completeness.sh`.
- Existing 7-point rows and specialist dispatch become registry rows so their omission is
  gated, not prose-hoped.
- No stage renumbering; the ICM-GATE hook, `cmd_init` freezing, and `.manifest` are reused
  unchanged.

## 11. Out of scope (do not creep)

- Judging verdict *quality* (see 7). This system guarantees answered, not answered-well.
- A general predicate language for `applies_when` - a fixed named set (4.2) only; add
  predicates as needed, do not build an expression evaluator.
- Auto-fixing gaps. The gate reports and blocks; humans/authors act.
- Applying this outside pr-review until it has earned its keep on one skill.
