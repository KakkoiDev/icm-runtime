# 01-publish

<!-- ICM-GATE tools="publish" run="checks/receipt.sh" -->

The `publish` action is gated: it stays blocked until this stage has produced
`output/receipt.md`. The gate above is frozen into the run and hashed in the
`.manifest`; `checks/receipt.sh` is its checker (`test -s output/receipt.md`).

## Process
1. Do the work that produces the receipt. For the demo, create it by hand:
   `echo ok > <run>/01-publish/output/receipt.md`
2. With the receipt present, a `publish` tool call passes the gate; without it, the
   gate denies. Drive it with `icm.sh gate-check --tool publish`.

## Outputs
| Artifact | Location | Format |
|----------|----------|--------|
| Receipt | output/receipt.md | the non-empty marker the gate checks for |
