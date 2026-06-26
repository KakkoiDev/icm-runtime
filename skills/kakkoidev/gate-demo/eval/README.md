Holds `*.test.sh` checks run by `icm.sh eval kakkoidev/gate-demo` (each runs from the skill dir).

- `structure.test.sh` - scaffolding guard: SKILL.md name, the `01-publish` stage with its `publish` gate, and an executable `checks/receipt.sh`. The gate's DENY/ALLOW behaviour is covered by the runtime suite (`tests/gate.test.sh`).
