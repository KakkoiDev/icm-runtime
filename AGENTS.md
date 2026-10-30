# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Tests: `sh tests/gate.test.sh` (runtime) and each skill's `eval/*.test.sh`. See `CONTRIBUTING.md`.
- Seven gate.test.sh cases fail on a clean tree (`icm-gate.ts` refuses shell metacharacters in a
  gate `run=` command, so `grep -Eq '^RESULT: PASS$'` is rejected). Pre-existing, unrelated to
  skill work - compare against the base commit before blaming a change.
- `skills/*/tools/*` are `#!/bin/sh` and get **`/usr/bin/awk` and `/usr/bin/grep`**, but the shell
  an agent runs commands in has `grep` shadowed by **ugrep**, which accepts patterns BSD grep does
  not. Probe a regex with `/usr/bin/grep` explicitly, or a tool passes interactively and fails when
  the script runs it. `\t` and `\b` are not POSIX ERE and diverge GNU vs BSD - use explicit
  character classes.
- macOS `awk` is version 20200816 and does support `{n,m}` intervals; older one-true-awk builds do
  not, so keep intervals to awk, not to `sed`.
- `set -e` does NOT fire when a loop body ends in a failing `&&` list (`cmd && act`):
  bash 3.2 suppresses -e for every command of an AND-OR list but the last, and does not
  re-check the loop. A bare failing command as the body's last statement DOES exit. So a
  guard written as `match && emit` never aborts, and the same guard written bare aborts
  the whole script - verify which shape a script has before blaming either.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
