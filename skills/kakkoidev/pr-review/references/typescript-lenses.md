# TypeScript review lenses

Lenses for reviewing TypeScript diffs. Each is a class the type checker does NOT catch, which is
why a green `tsc` is not evidence against any of them. Every lens carries the real finding that
produced it.

Use these in stage 04 alongside `references/scars.md`. They are lenses, not a checklist: read the
diff through them, do not tick them.

---

## T1. A doc comment asserts an invariant the types do not hold

**The class.** A docblock, a type alias name, or a comment states what a value *is*, and a caller
then relies on that statement. Nothing enforces it. The type checker sees a string either way.

**Real finding.** A client module's docblock asserted that the `status.error` branch carries
server-authored user-facing text. The service that sets that field assigned the queue library's raw
job-failure reason to it with no mapping. The caller's `instanceof` check relied on the asserted
invariant, so the narrowing was decorative.

**How to review it.** When a diff adds or edits a comment that describes a value's provenance,
follow the value to its actual assignment site. If the assignment does not enforce what the comment
claims, that is a finding even though the code compiles and the tests pass.

**Not a finding.** A comment describing intent that no caller depends on.

---

## T2. `catch` binds `unknown`, and the diff stringifies it across a boundary

**The class.** In TS, `catch (e)` is `unknown` (or `any` under older configs). Any path that turns
it into a user-visible string ships whatever the throw site happened to put there, including
messages from a dependency that never intended a user to read them.

**Real finding.** HIGH, security. `status.error` carried the raw
`Error.message` of whatever the processor rethrew. Only one curated family was mapped, so a gateway
failure, and specifically a missing-gateway-key configuration error, rendered verbatim in a
user-facing notification. Proven by two revert probes: leaks on head, generic message on revert.

**How to review it.** For each new path from a `catch` to a user surface, a log line that reaches a
customer, or an API response body: is there an exhaustive map from error to message, or does an
unmapped error fall through? The fix belongs at the boundary that owns the mapping, not at the
consumer that displays it.

**Evidence that settles it.** A revert probe. Run the failure on head and on the pre-diff code and
compare what the user sees.

---

## T3. The narrowing is real but the discriminant is not

**The class.** `instanceof`, an `in` check, or a discriminated-union switch narrows correctly per
the types, while the runtime value never actually carries the discriminant. Common where a value
crosses a serialization boundary: a queue payload, an HTTP response, `JSON.parse`, or a worker
message. Classes do not survive serialization; the `instanceof` arm is dead.

**How to review it.** For every narrowing added on a value that crossed a process, network, or
queue boundary, find where the value is constructed after the crossing. If it is a plain object,
the class arm never runs.

---

## T4. Test files are in scope, and are frequently where the finding is

**Why this lens exists.** `alibaba/open-code-review` excludes test files from review by default.
That default is wrong for a TypeScript monorepo and is one of the reasons that tool was rejected as
a fit. On one reviewed PR, **four of seven review comments were on `.spec.ts` files.**

**How to review it.** Review `.spec.ts` / `.test.ts` diffs with the same weight as source:

- An assertion that cannot fail. A mock standing in for the thing under test. A matcher loosened
  until it passes.
- A field stripped before the comparison, so the test asserts a subset of what it claims.
- A snapshot updated in the same commit as the behavior change, which records the change rather
  than testing it.
- A test deleted or skipped with no replacement. Deletions are the easiest thing to miss in a diff
  that is mostly additions.
- A regression test that does not fail on revert. If it passes both ways it tests nothing.

---

## T5. `any`, `as`, and non-null `!` introduced by the diff

**The class.** Each is an explicit instruction to stop checking. They are sometimes correct and
always worth one sentence in the PR.

**How to review it.** For each occurrence the diff ADDS:

- `as` on a value from outside the program (network, `JSON.parse`, an environment variable, a DB
  row) is an unvalidated assumption about data the program does not control. Ask what validates it.
- `!` on a lookup that can miss (`Map.get`, array index, optional chain result) is a runtime throw
  waiting for the empty case.
- `any` crossing a module boundary silently disables checking in every consumer downstream, not
  just at the site.

**Not a finding.** `as const`. A cast inside a type guard that the guard itself validates.

---

## T6. Environment variables read at module scope

**The class.** A module-scope environment read is evaluated at import time. It is then baked in,
untestable without module reset, and often absent in exactly the environment that matters.

**How to review it.** Is the read at module scope or inside the function? Is there a defined
behavior when the variable is absent, or does it silently become undefined and flow onward? An
undefined that reaches a comparison is usually a silent false, not an error.

---

## T7. Sequential `await` in a loop that had no reason to be sequential

**The class.** `for (const x of xs) { await f(x) }` is N round trips. It is correct, it is invisible
to the type checker, and it is frequently the whole latency story.

**Real example.** An agent that re-types a document's rows through a tool call in 30-row batches:
roughly 13 sequential model calls for a 385-row document.

**How to review it.** Is the loop order-dependent, or is it sequential by accident? If order does
not matter, it is a batch or a bounded-concurrency map. Say what the cost is in round trips, not
"consider parallelising".

**Not a finding.** A loop that must be sequential (rate limit, cursor pagination, ordered writes).
Say so rather than staying silent, so the next reviewer does not re-raise it.

---

## T8. Type-only changes with runtime consequences

**The class.** Widening a parameter type, making a field optional, or relaxing a return type
compiles everywhere and changes what callers may now pass. The diff looks like a type change; the
blast radius is runtime.

**How to review it.** When a diff widens a type or adds `?` to a field, find the consumers that
previously relied on the narrower guarantee. `strictNullChecks` catches the direct reads; it does
not catch a consumer that passes the value onward to something that spreads or serializes it.

---

## T9. Library and framework failure semantics, verified at the pinned version

**The class.** The diff calls into a library or framework and handles the success path. What the
library does on reject, throw, `false`, or retry is assumed from memory. The type checker sees a
`Promise<void>` either way; it says nothing about whether the failure ever reaches the caller.

**Real findings.** React Hook Form `handleSubmit` resolves without calling `onValid` when the
resolver fails, and throwing inside `onInvalid` leaves `isSubmitting` stuck. An RTK Query
`FETCH_ERROR` carries no `data`, so `e.data.error` throws inside the error handler. Next.js
`router.push` rejects asynchronously and resolves `false` on cancel. An agent loop retries on a
`{success:false}` tool result, so a per-call failure report shows an error on a run that then
succeeds. One rejected send that clears a whole queue drops callers already told success.

**How to review it.** For every changed call into a library or framework (form libraries, router,
fetch/RTK, agent loops, queues), state what happens on reject / throw / `false` / retry and whether
the failure reaches the caller that needs it. Verify against the library source at the version the
lockfile pins (`node_modules/<pkg>`), not memory or docs, and cite the file and line.

**Evidence that settles it.** A citation into the pinned library source, or a probe that makes the
library fail and records what the caller observed.
