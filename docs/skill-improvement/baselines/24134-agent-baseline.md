# Review: [NONE-31099] add ESignatureParticipant.use2FA (additive migration, no drops) [PR1/3]

**Verdict**: SHIP WITH FIXES
**Rationale**: Genuinely additive, no DROPs - but the unconditional in-transaction backfill UPDATE holds the ALTER's ACCESS EXCLUSIVE lock on `ESignatureParticipant` for the UPDATE's full duration with NO `lock_timeout`, reintroducing the exact P2024 head-of-line-blocking pattern the PR claims to have eliminated. Safety rests on an unverified "prod has zero use2FA=true rows" claim.

**Date**: 2026-06-30
**Scope**: 3 files, +24, -3
**PR**: [NONE-31099] add ESignatureParticipant.use2FA (additive migration, no drops) [PR1/3] - meetsmore/meetsone#24134 (MERGED; retrospective review)
**Specialists**: base, migration/data-integrity (differential), dead-code/blast-radius
**Buckets**: prod=0, generated=1 (kysely db-types), migration/SQL=1, schema=1

## 7-Point Validation
| # | Check | Status | Note |
|---|-------|--------|------|
| 1 | Requirements traceability | PASS | Additive `use2FA` column + backfill + `@deprecated` markers all map to the migration task. PR2/PR3 carry behavior. |
| 2 | Dead code | PASS (with note) | `ESignatureParticipant.use2FA` has zero readers/writers in app code (written only by the one-time backfill). Acceptable for an explicit PR1/3 schema-only foundation; flagged below. |
| 3 | Scope | PASS | 3 files, all serve the staged migration. No drive-bys. `@deprecated` JSDoc is in-scope. |
| 4 | Security | PASS | No auth/crypto/input surface touched. 2FA enforcement logic unchanged (still reads `request.use2FA`). |
| 5 | Performance | FAIL | In-transaction backfill UPDATE holds ACCESS EXCLUSIVE on `ESignatureParticipant` for the UPDATE duration; no `lock_timeout`. P2024 risk if any rows match or the ALTER queues behind a long txn. |
| 6 | Test coverage | FAIL | New column has no test (no reader/writer to test) and the backfill SQL has no automated regression. Static-only: no runner exercised. New prod symbol untested = HIGH per gate. |
| 7 | Production readiness | PASS (with note) | No flag/rollout needed for a no-behavior schema add, but the "no-op" claim is unverified (see Issue 1). |

## Critical Issues

### Issue 1
**File**: `apps/server/prisma/migrations/20260626032759_add_participant_use_2fa/migration.sql:9-13`
**Severity**: HIGH
**Category**: Data Integrity / Migration lock risk
**Found by**: base, migration auditor
**Description**: Prisma executes each migration file in a SINGLE transaction (`migrate deploy` wraps the file in `BEGIN ... COMMIT`). The `ALTER TABLE ... ADD COLUMN` (line 2) takes an `ACCESS EXCLUSIVE` lock on `ESignatureParticipant` - the strongest lock, conflicting with even plain `SELECT`. "Metadata-only" controls work done, NOT lock strength: every `ADD COLUMN` grabs `ACCESS EXCLUSIVE` regardless. That lock is held until COMMIT (PG never downgrades mid-transaction), i.e. through the entire subsequent `UPDATE` (lines 9-13). For the whole ALTER+UPDATE+commit window, ALL reads and writes to `ESignatureParticipant` are blocked. With no `lock_timeout` configured anywhere in the migrate-deploy path (the only `lock_timeout = 0` in the repo is the pg_dump default in the SQUASH baseline `00000020260520_SQUASH/migration.sql:91`, which means "wait forever"), if the ALTER cannot immediately acquire ACCESS EXCLUSIVE (any open txn holding even ACCESS SHARE - a slow SELECT, idle-in-transaction, autovacuum) it blocks AND queues every subsequent lock request behind it: head-of-line blocking. App connections pile up waiting on the table, exhaust the pool, and surface as **P2024 (timed out fetching a connection from the pool)** - the exact signature that reverted #22980 / #23075. The PR's mitigation ("no DROP") removes one source of long locks but is necessary-not-sufficient: a bare `ADD COLUMN` with no `lock_timeout` fully reproduces P2024 under the same concurrency. The ADD COLUMN is correctly metadata-only on PG11+ (constant `DEFAULT false`, no rewrite, NOT NULL satisfied by the non-volatile default) - the risk is lock strength + hold duration, not a rewrite.
**Fix**: Split into two migration files - (a) `ADD COLUMN` alone (instant, releases lock immediately on commit), (b) the backfill UPDATE in its own migration with `SET LOCAL lock_timeout = '...'; SET LOCAL statement_timeout = '...';` at the top, and batch the UPDATE (e.g. by `tenantId` or id ranges) if any production rows actually match. This removes the held-lock-spanning-UPDATE entirely.
**Regression**: Seam = a migration-lint check (the repo already runs `verify-migration.sh` against a real PG). Assertion: a migration file MUST NOT combine `ALTER TABLE` with a non-trivial `UPDATE` in the same (implicit) transaction without a `SET LOCAL lock_timeout`. Fails-on-revert: re-adding the combined ALTER+UPDATE without lock_timeout trips the lint. SPEC ONLY - hand to qa.
**Mutation**: n/a (read-only review; no worktree/runner per constraints).

### Issue 2a
**File**: `apps/server/prisma/migrations/20260626032759_add_participant_use_2fa/migration.sql:6`
**Severity**: MEDIUM
**Category**: Misleading Claim (will cause the next P2024)
**Found by**: migration auditor
**Description**: The migration comment states the backfill takes "row-level lock のみで ACCESS EXCLUSIVE は取らない" (row-level locks only, does not take ACCESS EXCLUSIVE). This is factually false. The preceding `ADD COLUMN` in the same transaction takes `ACCESS EXCLUSIVE` on `ESignatureParticipant` and holds it through commit (Issue 1). This is the most dangerous line in the migration's reasoning: it encodes the belief that `ADD COLUMN` is lock-free, which will mislead the next author into omitting `lock_timeout` again - reproducing exactly the failure this PR claims to have learned from. Metadata-only is not lock-free.
**Fix**: Delete or correct the comment. State plainly: `ADD COLUMN` takes a brief-work but full-strength ACCESS EXCLUSIVE lock; the protection is `SET LOCAL lock_timeout`, not the absence of a rewrite.
**Regression**: covered by Issue 1's migration-lint (a lint enforcing `lock_timeout` makes the false comment irrelevant). SPEC ONLY.
**Mutation**: n/a (comment).

### Issue 2
**File**: `apps/server/prisma/migrations/20260626032759_add_participant_use_2fa/migration.sql:5-6`
**Severity**: HIGH
**Category**: Unverified Claim / Data Integrity
**Found by**: base
**Description**: The comment asserts the backfill is "実質 no-op" in production because LD flag `isReleaseESignature2fa` is unreleased, so no `ESignatureRequest.use2FA = true` rows exist. This is an unverified production-data hypothesis, and the LD flag does NOT gate the backend write. The flag is checked only on the FE (`apps/web/src/components/templates/ESignatureCreatePage/hooks.ts:200` forces `use2FA=false` when the flag is off). The backend `e-signature.service.ts:1313` and `:1140` write `use2FA: dto.use2FA ?? false` with no flag check. Any direct/integration API caller, any tenant with the flag forced on, or any seed/QA path that set `use2FA=true` produces `true` rows. If such rows exist, the backfill is NOT a no-op and Issue 1's lock window becomes real, not theoretical. The "no rows" claim cannot be confirmed from the repo.
**Fix**: Before deploy, confirm the row count with `SELECT count(*) FROM "ESignatureRequest" WHERE "use2FA" = true;` against each target environment (prod + staging). If > 0, the staged-and-batched backfill of Issue 1's fix is mandatory, not optional. Record the count in the PR/ticket as evidence rather than asserting "no-op".
**Regression**: Seam = pre-deploy data check captured in the migration runbook. Assertion: row count recorded per environment; if non-zero, batched-backfill path used. SPEC ONLY - hand to qa.
**Mutation**: n/a.

## Findings by Category

### Dead Code
- `ESignatureParticipant.use2FA` (`apps/server/prisma/schema/e-signature.prisma:118-119`; backfilled at `migration.sql:9-13`). Severity: MEDIUM (downgraded from the usual HIGH). Grep across `apps/server/src` + `apps/web/src` (excluding tests + db-types) shows zero readers and zero writers of the participant-level column - `buildParticipantsData` (`e-signature.service.ts:3802-3855`) does not set it, and every 2FA read path (`e-signature-auth.guard.ts:186-187`, `e-signature.service.ts:2018/2039/2090`, `e-signature.queries.ts:24-25/37-38`) still reads `eSignatureRequest.use2FA` via the relation, NOT `participant.use2FA`. The column is dead at runtime until PR2/PR3. This is consistent with the PR's stated "下地のみ / foundation only" scope, so it is acceptable - but it is a real risk vector: if PR2/PR3 stall, prod carries a backfilled-once column that silently drifts from `request.use2FA` on every new request (new participants get the `@default(false)`, never the request's value). Action: keep, but ensure PR2 lands within the same release train, or have PR1 also write the participant column on create so it never drifts.

### Scope Drift
- None. All three files (migration SQL, prisma schema, generated kysely types) serve the single staged-migration purpose.

### Security
- None. No change to authn/authz, input handling, or crypto. 2FA enforcement (`is2FAEnforced && use2FA && !otpVerifiedAt`) is untouched and still reads the request-level flag.

### Performance
- See Issue 1 (the only performance concern, and it is the central one).

### Architecture
- The `@deprecated` markers on `ESignatureRequest.use2FA`, `ESignatureRequest.owner`, and the `ESignatureOwner` model (`e-signature.prisma:50,55,82`) are correct for a staged deprecation and physical-delete-later strategy. Sound given the two prior P2024 reverts.

### Code Quality
- Generated kysely type `use2FA: Generated<boolean>` (`db-types.d.ts:1773`) correctly matches the schema's `@default(false)`. The `@deprecated` JSDoc on the request-level type (`db-types.d.ts:1804`) matches the prisma change. Generated bucket verified against source - no manual drift.

## QA Cross-Reference
No QA-REPORT-JSON provided.

## Recommendations
- LOW: The migration comment is in Japanese prose asserting a production fact ("本番は ... 実質 no-op"). Replace the assertion with the actual measured row count (Issue 2) so future readers see evidence, not a claim.
- LOW: Consider having PR1 set `use2FA` on participant creation in `buildParticipantsData` (`e-signature.service.ts:3802`) by threading the request's `use2FA` through, so the new column never drifts from the source-of-truth between PR1 and PR2 landing. Avoids a silent-correctness window if the stack stalls.

## Verification
- **Suite**: not run. Constraint: READ-ONLY, no mutation testing, no worktree. PR body claims "e-signature 統合テスト 208 passed" locally - not independently reproduced here.
- **Mutation**: n/a (worktree mutation testing prohibited by task constraints).
- **Static lock analysis** (independent + cross-checked by migration auditor): ADD COLUMN with constant DEFAULT = metadata-only on PG11+ (no rewrite; NOT NULL satisfied by non-volatile default). But metadata-only != lock-free - it still takes ACCESS EXCLUSIVE. ALTER+UPDATE share one Prisma transaction (`migrate deploy` = BEGIN...COMMIT) -> ACCESS EXCLUSIVE held from ALTER through the UPDATE and commit; PG never downgrades mid-transaction. No `lock_timeout` in migrate-deploy path (verified: only pg_dump default `lock_timeout=0` in SQUASH baseline) -> head-of-line lock-queue blocking = P2024. The migration comment's "ACCESS EXCLUSIVE は取らない" claim is FALSE (Issue 2a). UPDATE scan: `r.use2FA=true` has no index (seq scan on requests, filters to zero on prod), join probes participants via the `(eSignatureRequestId, participantOrder)` unique B-tree. Join column `eSignatureRequestId` is the correct non-unique FK (one request -> many participants); backfill semantics (copy request flag to all its participants) match the "send-unit -> signer-unit" intent (verified against `e-signature.prisma:107-108`).
- **Live (MCP, read-only)**: not performed. The decisive unknown - production count of `ESignatureRequest.use2FA = true` - was NOT queried (would require DB access not in scope). This is the single fact that converts Issue 1 from theoretical to live; flagged for pre-deploy verification.

## Test handoff (to qa)
Per HIGH finding:
- Issue 1: migration-lint regression - reject any migration combining `ALTER TABLE` + non-trivial `UPDATE` in one implicit transaction without `SET LOCAL lock_timeout`. Reuse `apps/server/prisma/scripts/verify-migration.sh` harness against real PG.
- Issue 2: pre-deploy data smoke (requires DB creds review does not hold): `SELECT count(*) FROM "ESignatureRequest" WHERE "use2FA" = true;` on prod + staging. Expect 0 to validate the no-op claim; any non-zero count mandates the batched-backfill fix and re-review.

<!-- REGRESSION-SPEC-JSON
{
  "regressions": [
    {"finding": "Issue 1 - ALTER+UPDATE single-transaction lock, no lock_timeout", "file": "apps/server/prisma/migrations/20260626032759_add_participant_use_2fa/migration.sql:2-13", "seam": "migration lint via verify-migration.sh against real PG", "assertion": "a migration file must not combine ALTER TABLE with a non-trivial UPDATE in one implicit transaction without SET LOCAL lock_timeout; ALTER and backfill split into separate files", "fails_on_revert": true},
    {"finding": "Issue 2 - unverified no-op backfill claim; LD flag does not gate backend write", "file": "apps/server/prisma/migrations/20260626032759_add_participant_use_2fa/migration.sql:5-13", "seam": "pre-deploy data check captured in migration runbook", "assertion": "count of ESignatureRequest.use2FA=true recorded per target env; non-zero forces batched backfill path", "fails_on_revert": true}
  ],
  "live_smokes": [
    {"name": "prod/staging use2FA row count", "creds_needed": ["read-only DATABASE_URL for prod", "read-only DATABASE_URL for staging"], "steps": "Run: SELECT count(*) FROM \"ESignatureRequest\" WHERE \"use2FA\" = true;", "expect": "0 confirms the no-op claim; any non-zero count invalidates the as-merged migration's lock-safety assumption and requires batched backfill + re-review"}
  ]
}
-->
