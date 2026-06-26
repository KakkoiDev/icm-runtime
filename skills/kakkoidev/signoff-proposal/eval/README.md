Holds `*.test.sh` checks run by `icm.sh eval kakkoidev/signoff-proposal` (each runs from the skill dir).

- `structure.test.sh` - scaffolding guard: SKILL.md name + namespace, all three stages present and non-empty, each stage carries its `ICM-TOOLS` contract, and the publish stage keeps its `ICM-GATE`. Does not test proposal content (this skill is model-mediated).
