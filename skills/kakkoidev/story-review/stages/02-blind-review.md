# Stage 02: Blind review (10 lenses + refutation)

<!-- ICM-TOOLS expect="(Read|Write)" -->
<!-- ICM-GATE tools="Write" run="checks/gathered.sh" -->

Review `output/story-body.md` cold, through the 10 lenses below, then kill your own
weak candidates in a mandatory refutation pass (step 11). You have not read
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
| Schema facts | ../01-gather/output/schema-facts.md | ground truth for lens L5 (record shape) |
| Implementation facts | ../01-gather/output/impl-facts.md | ground truth for L5 (enum membership, derived state) and L10 (what the existing surface really does) - read it before writing any L5 or L10 finding |
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
   For a matching rule specifically ("fields whose API name matches are copied"),
   name the compatibility question the rule leaves open: what happens when the
   identifier matches but the TYPES differ - copy, coerce, reject, drop, or log?
   A matching rule that only says how names line up has not said what it does
   with a match it cannot honor.

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
   Two shapes that are NOT contradictions and are missed if you only hunt for
   contradictions:
   (a) **Unowned overlap.** Two or more siblings each define the same
       state-changing outcome off a different trigger for the same lifecycle
       event, and no doc names which one owns it or what the shared idempotency
       key is. Nothing contradicts anything; the outcome just happens two or
       three times. Name every story that can produce the outcome and state that
       no owner is designated.
   (b) **Canonical-source divergence.** A sibling links a canonical definition
       page (a field/attribute spec) for a concept and this doc restates a
       shorter inline version instead, or vice versa. Flag the divergence and say
       which fields the two lists disagree on - "probably just shorter" is the
       assumption that lets two field sets drift apart.

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
   deleted after this doc's rule already fired off of it; (d) the RECOVERY path
   after a committed action, not just the cancel path before it - a doc that
   carefully specifies "cancel before confirming leaves no orphan state" has
   usually said nothing about undoing, deleting, or archiving the thing it just
   committed. Check whether the post-commit sequence can reach the exact state the
   pre-commit rule exists to prevent; if it can, that is the finding, and it is
   sharper than the generic gap because the doc already agreed the state is
   forbidden. An AC that only covers the happy-path transition and is silent on a
   transition you can construct is a gap - name the exact transition, don't just
   gesture at "edge cases."

5. **L5 - Implementation ground truth.** Cross-check every field/column/label name
   the doc uses against `schema-facts.md`. A name in the doc that doesn't appear in
   the schema (or maps to a differently-named real field) is a finding: state the
   doc's name, the real name, and whether they're the same underlying data under
   different labels or genuinely different things.
   Then check `impl-facts.md` for the two mismatches a field-name sweep cannot see:
   (a) **Derived vs stored state.** The doc names a status/state and treats it as
       something a user sets or the system stores. If no such field exists but
       `impl-facts.md`'s referencing files compute it from other columns, the
       doc's trigger is underspecified in a specific way worth stating: is the
       state meant to become a real persisted field, is the derivation rule the
       real trigger (and where is it written down), or is the true trigger a
       different event entirely? Say which of those the doc leaves open. Do not
       soften this to "naming inconsistency" - an engineer implementing against
       a state that isn't stored will pick an event, and the doc does not say
       which.
   (b) **Capability absence.** If the doc assumes a target-addressable capability
       for an entity (custom fields, permissions, a phase type) and
       `impl-facts.md`'s "as a member of another enum" section for that entity is
       empty, the type system does not support the claim yet. Cite the empty
       section as the evidence. An entity referenced by no source file at all is
       the strongest form of this.

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
   When X is a sibling story rather than an external system, also check WHICH of
   X's rules the claim imports: a bare "same behavior as X" against a sibling that
   contains six separable rules (copy set, defaulting, uniqueness guard, archive
   behavior, an open question) imports the open question too. Say which rules the
   claim must enumerate.

9. **L9 - Actor and entry-path coverage.** Read every trigger the doc states and
   ask which actors and paths can produce it. Specifically:
   (a) **Non-interactive paths.** If a trigger is specified as a UI interaction
       ("changing the phase opens a form"), name the paths that reach the same
       state change without a UI - the external/public API, automation or workflow
       rules, CSV/bulk import, background jobs, admin tooling. A form cannot open
       for any of them. State what those paths should do instead: create the
       record automatically, reject the transition, or require a separate
       endpoint. Check `impl-facts.md`'s referencing files before asserting a path
       is unhandled today - one of these gets *narrowed* by real code more often
       than any other lens, and a finding that survives narrowing ("the existing
       API path handles today's records but the doc still does not say what it
       does once this new record type exists") is the stronger version.
   (b) **Permission baseline.** Does the doc say who is allowed to perform its
       action? Check both directions: this doc leaning on an undefined permission,
       AND a sibling leaning on THIS doc ("same permissions as <this doc's
       action>") when this doc never states one. The second direction is easy to
       miss because nothing in this doc looks wrong on its own.

10. **L10 - "Extension of an existing surface" scope claims.** Any phrase of the
    shape "an extension of the existing X," "reuses the current Y," "same screen
    as Z" is a claim that X's current behavior is a subset of the new behavior.
    Verify it: find X in `impl-facts.md`'s referencing files and read what it
    actually does now. When X already performs side effects the doc never mentions
    - creating or converting other records, feeding other screens' figures,
    enforcing its own required fields, having mutually exclusive modes - the doc
    has silently taken a scope decision it never surfaced. State the side effect,
    then state the unanswered question: is it preserved, removed, or made
    conditional? This is the lens most likely to change what the story is
    actually asking for, because "just an extension of an existing input" is how
    a major product decision gets phrased as a small one.

11. **Refutation pass (MANDATORY - do this before writing the final file).** Every
    candidate from lenses 1-10 is a hypothesis. Take each one and argue the other
    side: is it answered elsewhere in this same doc, in a fetched sibling, or by
    `impl-facts.md`? Is the concern real but narrower than stated? Would a
    reasonable implementer never actually hit it? On a real run this pass killed 7
    of 25 candidates, and it is the one step credited with the review's precision -
    a run that carries every candidate forward has not reviewed, it has
    brainstormed.
    - A candidate you kill does NOT disappear. Write it as its own
      `## R<n> - <lens> - refuted` block with a `Killed:` line naming what refuted
      it. A silently-dropped candidate is unauditable, and the next reviewer will
      regenerate it.
    - A candidate you narrow stays as an `## F<n>` block with `Confidence: Partly
      refuted` and the narrowing stated in the concern text.
    - Do not kill a candidate merely because you suspect another story covers it -
      that is L6(b)'s explicit rule, and "probably handled elsewhere" is not
      refutation.

Write each surviving finding as its own block headed `## F<n> - <lens> - <severity>`
(severity one of `high`/`medium`/`low`; the id is line-leading so a mention
mid-prose elsewhere never creates or steals a block). Never use a `###` header
inside a block - the downstream scorer ends a block at ANY `##`-level header,
including `###`, so a nested header truncates its own finding. Each block carries,
in this order:

```
## F<n> - <lens> - <severity>
> <direct quote from story-body.md the finding is about>
Confidence: <Confirmed|Strongly supported|Supported|Plausible|Partly refuted>
Evidence: <the schema-facts.md / impl-facts.md line, sibling quote, or "story text only">
<one or two sentences of the concern>
Risk: <what goes wrong if it ships unresolved>
```

`Confidence` is a distinct axis from severity and the vocabulary is closed -
`tools/grounding-audit` rejects anything outside it:
- **Confirmed** - story text plus a real schema/code/sibling fact, both cited.
- **Strongly supported** - story text plus available evidence, not code-confirmed.
- **Supported** - a valid spec gap from the story text alone.
- **Plausible** - a real risk, but it depends on implementation you did not verify.
- **Partly refuted** - the original candidate was too broad; the narrowed version
  is what stands.

A high-severity `Plausible` finding is legitimate and common. Do not upgrade
confidence to match severity, and do not downgrade severity because confidence is
low - conflating the two is what produced report tables that had to be re-labelled
by hand afterward.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done kakkoidev/story-review --stage 02-blind-review
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Findings | output/findings.md | FIRST LINE is `Independence: fresh (...)` or `Independence: re-review (...)` per step 0. Then one `## F<n> - <lens> - <severity>` block per surviving finding, id line-leading, each carrying a `> ` story quote, a `Confidence:` line from the closed vocabulary, an `Evidence:` line, the concern, and a `Risk:` line - no `###` headers inside a block. Then one `## R<n> - <lens> - refuted` block per candidate killed in step 11, each with a `Killed:` line. A lens with nothing to report says so in one line rather than being omitted silently. |
