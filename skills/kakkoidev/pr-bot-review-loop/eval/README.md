# Eval: pr-bot-review-loop

Run with `icm.sh eval kakkoidev/pr-bot-review-loop`. Each `*.test.sh` runs from the skill
dir and exits 0 on pass.

Every test freezes a rule the loop once broke, in the shape it broke:

| Test | Freezes |
|------|---------|
| `structure.test.sh` | the three stages, their gates, and that all twelve rules survive **with their reasons** |
| `request-fired.test.sh` | R1 - a mention-less request is UNFIRED, and bot activity predating the request is not evidence the round fired |
| `ledger-audit.test.sh` | R1..R11 as the audit sees them, each failing case and the clean one; that `converged` mode does not gate on the R11 cleanup; and that `closed` mode also requires every request comment collapsed, including the last |
| `revert-proof.test.sh` | R4 - an assertion that passes in both directions |
| `gather-ci.test.sh` | R8 - a green wrapper over a failed step, and a red gate that may be infrastructure |
| `mark-superseded.test.sh` | R11 - the latest bot report and a human's comment are never collapsed, and the whole cleanup is one batched call |
| `gather-requests.test.sh` | R11 extended - every review-request comment across all rounds is collected with `superseded=yes`, including the newest; an unfired request ("-") is never a target; duplicates dedup |
| `loop-exit.test.sh` | the convergence gate, including that it stays hermetic (no GitHub CLI, no approval click per Write) |

The tools that talk to GitHub take their CLI from `$GHBIN` (default `gh-axi`), so these
tests stub it and never touch the network.
