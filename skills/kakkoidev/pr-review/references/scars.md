# Review lenses

Generalized review principles distilled from real past misses. Specifics (tickets, file paths,
values, names, dates) are deliberately removed so the lens is portable across repos and cannot
leak the answer to any particular PR. Read before judging a diff; treat each as something to
actively check, not a box to tick.

## Findings are hypotheses - verify before asserting
- Read every file in the diff end-to-end before judging. A partial read is not a review.
- A finding is a hypothesis: read the source and confirm it before asserting; expect some to collapse on inspection.
- To verify a "stale / wrong / missing / unused" claim, check what the truth IS - not merely that the flagged text exists. Name the decisive fact before marking a finding confirmed.
- Attributing intent or authorship: who last touched a line (blame) is not who wrote the logic; find the introducing change before asserting why code is the way it is.

## The ticket / AC is input, not ground truth
- Verify a ticket's premises before trusting them: "current behavior" claims against the running code, "X already does this" parity claims against X's actual code, any new rule/constraint against the spec line that requires it, the bug against a real reproduction.
- An AC or audit finding that asserts framework behavior or a NEW business rule is a hypothesis - confirm it in the framework source or spec before accepting. Absent from both, it is a human decision, not something to implement. Evidence against a premise falsifies it first, scopes it second.
- Check the diff against its stated ACs; a fix that violates an AC is wrong even if it "works".
- Never assert a before/after observable you have not personally seen.

## Read the duals (removed / renamed values)
- When a diff CHANGES or REMOVES a user-visible value (label, message, enum, rendered string), search the whole test tree (unit, snapshot, e2e) for assertions on the OLD value - one still asserting it is a latent break, even if that suite stays green on the PR pipeline.
- When a diff renames or removes a symbol or key, grep the exact OLD symbol repo-wide for orphaned references (dead code); verify against the file/package that actually defines it. An empty grep in a location you guessed is not proof of absence - it is evidence you grepped the wrong place.
- Separate the code-logic claim ("this breaks") from the CI claim ("the pipeline goes red"); assert only the one you verified.

## Refuse busywork and defensive noise
- Flag guards for paths already covered elsewhere ("for future callers" is almost always unnecessary).
- Flag wrapping / memoization / abstraction justified by "consistency" rather than a real need.
- Flag comments that justify the code's existence (intent, taxonomy) instead of describing what it does.

## Tests
- A behavior-changing fix needs a regression test that fails on revert. No such test = not done.
- A test that locks incorrect behavior is worse than no test - read the AC before the assertion.

## Scope to what is actually new
- Before reviewing, check whether the branch/PR just aggregates already-reviewed or merged sub-PRs; match effort to what is genuinely new since the last review.
- Prefer the written convention/spec over sibling-code precedent when they conflict; observed history is not precedent when a documented convention exists.
- Process/people facts (owners, schedules, meetings) cannot be verified from source - mark them unverified or confirm with a human.

## Checklist, uniform bar, anti-bias
- Reconcile the PR against its own template's mandatory checklist. Audit EVERY item to the same standard; tag each verdict verified (ran a check) or asserted (judgment). A judgment "met" is unverified until you exercise what it claims - read the doc for "docs sufficient", inspect the branches for "enough tests", look at the emitted output for "observability" - never infer adequacy from a diffstat or a count. The author's ticked box is a claim, not evidence.
- Bias alarm: if the only gap you surface is the one a human hinted at, or every scannable item passes while every judgment item gets an asserted pass, re-scrutinize what you waved through. Mechanical checkability is not importance.

## PR description hygiene (flag these)
- Flag hand-maintained file lists or counts in a PR description - the diff is the canonical list; they rot on rebase/amend. Name a file only to direct attention, never as a manifest.
- Flag over-claiming prose: the description should be what changed + one authoritative source per factual claim. Each extra specific claim is unverified surface a reviewer will rightly check; being wrong in verbose prose reads worse than a terse line. Don't narrate past errors - correct silently.

## Review independence
- On a re-review of the SAME PR, do a blind pass first (from the diff and runtime evidence only); read any prior review afterward and only to reconcile, re-deriving each verdict against source. A prior run's findings list is anchoring, not a second opinion. Disclose reduced independence.
