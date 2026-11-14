# Findings - meetsmore/use-ai PR 96 at a9d4e7a3 (expected review, precedence excerpt)

## Precedence changes

Detector: `detect-precedence-changes ../01-context/output/pr.diff` -> 3 rows. Callers of
`startRunSpan` passing `attributes`: AISDKAgent.ts:657 and any custom agent (exported API).

Precedence: packages/server/src/telemetry.ts:68 ...config.attributes vs ai.telemetry.functionId old-winner=...config.attributes new-winner=ai.telemetry.functionId intent=unstated test=missing finding=F1
Precedence: packages/server/src/telemetry.ts:68 ...config.attributes vs ai.telemetry.metadata.runId old-winner=...config.attributes new-winner=ai.telemetry.metadata.runId intent=partial(body: "runId / sessionId are applied after the metadata" - AISDKAgent path only) test=missing finding=F1
Precedence: packages/server/src/telemetry.ts:68 ...config.attributes vs ai.telemetry.metadata.sessionId old-winner=...config.attributes new-winner=ai.telemetry.metadata.sessionId intent=partial(body: "the existing session id fallback still wins" - AISDKAgent path only) test=packages/server/src/agents/AISDKAgent.trace-attributes.test.ts:127 finding=F1

## F1 - MEDIUM - behavior-change
File: packages/server/src/telemetry.ts:68
Description: `...config.attributes` moved from last to first in the run span attributes. Before,
a caller's `config.attributes` won over `ai.telemetry.functionId`, `ai.telemetry.metadata.runId`
and `ai.telemetry.metadata.sessionId`; now those three keys win over the caller. The body states
the new order only for the AISDKAgent telemetryMetadata path; `startRunSpan` is exported, so a
custom agent that set any of the three keys loses its value silently.
Fix: spread `config.attributes` last again and drop runId/sessionId from the metadata AISDKAgent
copies, or state the reversal for every caller.
Fix shape: contract; callers: custom agents passing those keys lose them.
Regression spec: seam `startRunSpan({ runId, sessionId, attributes: { 'ai.telemetry.metadata.runId': 'caller', 'ai.telemetry.functionId': 'caller' } })`
with an in-memory exporter; assert the root span keeps the caller values; fails on the a9d4e7a
order. The existing test (AISDKAgent.trace-attributes.test.ts:127) pins sessionId through
AISDKAgent only.
Value: introduced-by-diff=yes in-scope=yes merge-decision=yes floor=pass -> proposed: inline
