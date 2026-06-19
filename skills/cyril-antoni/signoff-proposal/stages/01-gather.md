# Stage 01: Gather evidence

<!-- ICM-TOOLS expect="(pup|search_datadog_spans|aggregate_spans|get_datadog_trace|bq_query|redash_execute_query|search_web|WebSearch)" -->

Pull the real numbers behind the decision, and for each one capture a clickable link to
the source data. This stage is the difference between a proposal that asserts and one
that proves. Adjust the expected tools above to whatever data source actually backs the
decision (Datadog/pup is the worked example; could be BigQuery, Redash, a PR, a report row).

## Inputs
| Source | Location | Scope |
|--------|----------|-------|
| Decision to propose | Chat message | What needs sign-off, and the rejected alternative |
| Parent ticket | Chat message / URL | The ticket the proposal sub-page will live under |
| Data source | Chat / project | Where the backing numbers live (e.g. Datadog APM, a DB) |

## Process
1. State precisely what decision is being put up for sign-off, and the one alternative it beat.
2. Pull the headline numbers from the data source. For EACH number capture: the value, the
   query used, the time window, and a clickable source URL. For Datadog: aggregate for the
   distribution/baseline, search to obtain the canonical `traces_explorer_url`, and the
   trace deep link `<base_url>/apm/trace/<trace_id>` for any decomposition.
3. If a conclusion rests on a breakdown (e.g. "p95 is dominated by X"), capture the
   decomposition with per-component numbers, not just the headline. Keep tool payloads
   small: request summaries / `only_service_entry_spans` / specific fields, not full raw
   trace dumps. Large payloads dominate the run's token cost and crowd context.
4. Confirm the baseline is stable (compare two windows, e.g. 7d vs 28d) before anchoring a target to it.
5. Write `output/evidence.md`: the decision summary + every metric as `value | window | query | source URL`.

## After Output (MANDATORY)
```bash
bash ~/.agents/skills/icm/runtime/icm.sh stage-done cyril-antoni/signoff-proposal \
  --stage 01-gather
```

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Evidence | output/evidence.md | Decision summary; per-metric rows (value, window, query, clickable source URL); any decomposition with component numbers |
