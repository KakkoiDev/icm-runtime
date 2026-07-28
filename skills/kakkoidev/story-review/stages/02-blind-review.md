# Stage 02: Blind review (8 lenses)

<!-- ICM-TOOLS expect="(Read|Write)" -->
<!-- ICM-GATE tools="Write" run="checks/gathered.sh" -->

Review `output/story-body.md` cold, through the 8 lenses below. You have not read
this page's comments and must not go looking for them - a finding informed by
answers already given elsewhere is not a finding, it is a lookup, and it will
invalidate stage 03's score. Read the ENTIRE body before writing anything; a
partial read misses cross-references between its own sections.

**The same isolation rule from stage 01 applies here and for the rest of this
run:** never list, glob, or read any file under any OTHER run's directory
(`.icm/kakkoidev/story-review/<other-timestamp>/`). `prior-runs.tsv` (below) tells
you whether one exists - that is the full extent of what you may know about it.

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Story body | ../01-gather/output/story-body.md | the doc under review (this is the ONLY doc-derived input - do not fetch its comments) |
| Prior runs | ../01-gather/output/prior-runs.tsv | disclosure only - do not open any run directory it names, see the isolation rule above |
| Schema facts | ../01-gather/output/schema-facts.md | ground truth for lens L5 |
| Sibling bodies | ../01-gather/output/sibling-*.md (if present) | ground truth for lens L2 - read every one that exists before writing L2's section |
| Sibling manifest | ../01-gather/output/siblings-fetched.md | which siblings were fetched/why, or why L2 has no sibling grounding this run |

## Process

0. **Independence disclosure (write this first, one line, before any lens work).**
   Read `../01-gather/output/prior-runs.tsv` - its existence and row count only,
   never any other run's content. Write, as the first line of `output/findings.md`:
   `Independence: fresh (no prior run on this target)` if the file has no
   `same_target=yes` rows, or `Independence: re-review (N prior run(s) on this
   target: <timestamps>) - blind to their content by construction, disclosed by
   target-id match only` otherwise. This mirrors `pr-review`'s independence
   header - the point is not to skip a re-review, it is to never silently claim
   `fresh` when it isn't, and never pretend a blind run gains anything from a
   predecessor it was never allowed to read.

Apply every lens that has material in the doc. Not every lens fires on every doc -
say so plainly when one doesn't, rather than manufacturing a finding to fill a slot.

1. **L1 - Terminology ambiguity.** Check the WHOLE document, not just the
   Acceptance Criteria bullets - the Description/"So that" rationale prose,
   Background, and Misc sections use domain terms just as often and are easy to
   skim past because they don't look like requirements. Every domain term,
   abbreviation, or label used without being defined on first use (anywhere in the
   doc, including prose sections, not just ACs) is a candidate. Also flag: a rule
   stated only as compressed notation or shorthand (an equals sign, a symbolic
   ratio) that could be read two different ways: spell out both readings and say
   which the doc actually means - if you cannot tell, that is itself the finding.
   Also flag a copy/matching/derivation rule stated in the abstract with no worked
   example - state what example would resolve it.

2. **L2 - Cross-document contradiction.** If `../01-gather/output/sibling-*.md`
   files exist, read every one before writing this section - do not skip straight
   to "no material" without having read them. For every AC or bullet in this doc
   whose topic overlaps a fetched sibling (by concept - archiving, phase/status
   transitions, permissions, editing - not by requiring an explicit link between
   the two docs), check it against that sibling's actual current text. A rule in
   THIS doc that a sibling's rule would block or contradict is a finding, cite
   both sides with a quote from each. If no sibling files exist (no parent epic
   was given this run), say so explicitly and note that L2 could only check
   contradictions within this single document (there were none) - do not silently
   imply a full cross-document sweep happened when it structurally could not.

3. **L3 - Silent state-change / data-drift risk.** For every action that creates or
   mutates a record derived from another record, check two things: (a) is there any
   visible signal to the user that it happened, and (b) does it stay in sync if the
   source record changes afterward. "Creates silently, never re-syncs, no signal
   either way" is the highest-risk shape - flag it even if the doc treats it as
   obviously fine.

4. **L4 - State-machine completeness.** Enumerate the full state space the doc's
   rules operate over (every status/phase value, every "what if this happens
   twice" and "what if it happens out of the stated order"). Three transitions to
   ALWAYS name explicitly and check, even when the doc never mentions the
   mechanism exists (its silence on the mechanism is not evidence the transition
   can't happen): (a) archiving something the rules treat as a one-way state -
   what happens if it's un-archived / re-activated later; (b) two actors
   attempting the same state-changing action concurrently (a race, not just
   sequential repetition); (c) the upstream/source record itself being archived or
   deleted after this doc's rule already fired off of it. An AC that only covers
   the happy-path transition and is silent on a transition you can construct is a
   gap - name the exact transition, don't just gesture at "edge cases."

5. **L5 - Implementation ground truth.** Cross-check every field/column/label name
   the doc uses against `schema-facts.md`. A name in the doc that doesn't appear in
   the schema (or maps to a differently-named real field) is a finding: state the
   doc's name, the real name, and whether they're the same underlying data under
   different labels or genuinely different things.

6. **L6 - Unresolved-dependency leakage.** Two distinct checks, do both:
   (a) Flag any AC that talks about an attribute, field, or capability of an
   entity whose full shape is never defined anywhere in this doc (nor linked), and
   any AC whose behavior depends on an open question this doc marks unresolved, or
   on another story not yet written. State what's missing, not just that
   something's missing.
   (b) Separately, flag "introduced without prior establishment": a bullet that
   assumes or requires a capability (a custom-field system, a permission model, a
   status field) on an entity this doc is actively defining, where NO earlier
   bullet in this SAME document first establishes that the entity has that
   capability at all. This is a narrower, easy-to-miss case of (a) - the entity
   itself is well-covered by the doc, but this one capability of it is smuggled in
   by a single bullet with no setup. Do not treat "it's probably covered
   elsewhere in the epic" as resolving this - if THIS document doesn't establish
   it, flag it, even if you suspect another story owns it.

7. **L7 - Compliance/financial-correctness gaps.** If the doc touches money, tax,
   or a legally-relevant status (tax code, qualified-invoice/registration status,
   rounding, withholding), check whether that attribute is explicitly threaded
   through the whole flow described (from source record to the derived one) or
   only implied. A silent drop of a legally-relevant field between two steps is a
   finding, not a style note.

8. **L8 - External-authority claims.** Any sentence of the shape "same rules as X" /
   "follows X" / "inherits X's behavior" is a claim about a document or system this
   doc does not itself contain. If X is linked, and its actual current content
   confirms the claim, that's fine - move on. If X is not linked, not fetched, or
   you cannot verify it, flag the claim as unverified rather than accepting it.

Write each finding as its own block headed `## F<n> - <lens> - <severity>` (severity
one of `high`/`medium`/`low`; the id is line-leading so a mention mid-prose
elsewhere never creates or steals a block). Under the heading: a direct quote from
`story-body.md` the finding is about, one or two sentences of the concern, and
(where L5/L8 apply) the specific schema-facts.md line or missing-link that grounds
it.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/story-review --stage 02-blind-review
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Findings | output/findings.md | FIRST LINE is `Independence: fresh (...)` or `Independence: re-review (...)` per step 0. Then one `## F<n> - <lens> - <severity>` block per finding, id line-leading; each block quotes the exact doc text and states the concern in 1-2 sentences; L5/L8 findings cite the grounding schema-facts.md line or the unverified external claim explicitly. A lens with nothing to report says so in one line rather than being omitted silently. |
