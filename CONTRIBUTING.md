# Contributing

## Layout

- `skills/icm/runtime/` - the runtime (`icm.sh`) and harness adapters
  (`gate-hook.sh`, `icm-gate.ts`). Treat as the stable core.
- `skills/<namespace>/<name>/` - skills. Group by author namespace.
- `tests/gate.test.sh` - the regression suite.
- `ARCHITECTURE.md` - how it all fits together.

## Run the tests

```sh
sh tests/gate.test.sh
```

The suite is hermetic (it sandboxes `$HOME` under a tmp dir) and runs on Linux
and macOS in CI (`.github/workflows/test.yml`). Run it locally before every PR.

**Two hard constraints for any change to `icm.sh`, `gate-hook.sh`, or a `tools/`
script:**

1. **It must parse under bash 3.2** (macOS `/bin/bash`). The suite's case 0 lints
   every shell script with `/bin/bash` when present, because a parse error behind
   the `.*` gate-hook denies *every* tool call in a user's session. Do not rely on
   bash 4+ syntax.
2. **A bug fix needs a regression test** in `tests/gate.test.sh` that fails on the
   pre-fix code and passes after.

## Adding a skill

```sh
icm.sh new-skill <namespace>/<name> --stages frame,draft,tighten
```

This scaffolds `SKILL.md`, one stub per stage, a `tools/` dir, and an `eval/`.
Then:

- Write each stage's contract (`stages/NN-name.md`): an Inputs table, a Process,
  and Outputs. The agent reads only what the contract names.
- Put deterministic logic in `tools/*.sh` and gate checkers in `checks/*.sh`.
  Both are frozen into each run and covered by the `.manifest`.
- Declare verification where it matters:
  - `<!-- ICM-TOOLS expect="ERE" -->` - tools the stage is expected to call.
  - `<!-- ICM-GATE tools="ERE" run="checker" -->` - a mechanical precondition.
  - `<!-- ICM-CALL tool="..." args="..." -->` - a verifiable call contract.
- Write an `eval/*.test.sh`. For a script-backed stage, test the script's output
  deterministically (see `skills/kakkoidev/publish-to-notion/eval/render.test.sh`).
  For a model-mediated skill with no `tools/`, guard the scaffolding structurally
  (see `skills/kakkoidev/draft-report/eval/structure.test.sh`) - do **not** write
  a test that asserts model output; a test that locks weak behavior is worse than
  no test.

Run your eval with `icm.sh eval <namespace>/<name>`, then `./installer.sh` to pick
the skill up. `skills/kakkoidev/icm-demo/` is the canonical annotated reference for
every construct.

## Presentation

The talk lives in `docs/presentation/`: `deck.md` (slides) and `talk-track.md`
(speaker notes) are the sources, and both render on GitHub. Diagrams are
pre-rendered SVGs in `diagrams/` from `*.mmd` sources.

Rebuild both HTML files and the diagram SVGs in one step:

```
sh docs/presentation/build.sh
```

Diagrams render via a local `mmdc` if installed, else the Kroki API. To stay
fully offline, self-host Kroki and set `KROKI_URL`:

```
docker run -d -p 8000:8000 yuzutech/kroki
KROKI_URL=http://localhost:8000 sh docs/presentation/build.sh
```

A pre-commit hook re-renders the SVGs whenever a `.mmd` is staged - best-effort,
so it warns but never blocks a commit if the renderer is unavailable. Enable it
once per clone:

```
git config core.hooksPath .githooks
```

The generated `*.html` are gitignored; regenerate them with `build.sh`.

## Commits

Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`). Keep
commits atomic. Reference the behavior change, not the file list.

## Releases

Tag a version (`git tag vX.Y.Z`) and push the tag. The release workflow
(`.github/workflows/release.yml`) runs the suite on Linux + macOS and, if green,
cuts a GitHub release. Keep `CHANGELOG.md` and the `VERSION` in `icm.sh` in sync
with the tag.
