# How icm-demo works

This skill is a runnable showcase of the ICM runtime and a copyable authoring template.
Every stage drives one deterministic `tools/` script that captures real `icm.sh` output
as its evidence; the model only narrates the result in chat. Sealing is post-run.

## The four tools and where they run

| Tool | Runs as | Produces | Touches |
|------|---------|----------|---------|
| `tools/run-report` | Stage 01 body | `output/lifecycle.md` | the real run (read-only) |
| `tools/sandbox-tour` | Stage 02 body | `output/enforcement.md` | a THROWAWAY run in `mktemp` (isolated `HOME`+cwd) |
| `tools/show-telemetry` | Stage 03 body | `output/telemetry.md` | the real run (reify appends `reify` events to `events.jsonl`) |
| `tools/close-run` | POST-RUN finalizer | chat + `.icm-seals.log` | the real run (seals it) |

```mermaid
flowchart LR
    RR["run-report"] --> S1(["Stage 01 lifecycle"])
    ST["sandbox-tour"] --> S2(["Stage 02 enforcement"])
    ST2["show-telemetry"] --> S3(["Stage 03 telemetry"])
    CR["close-run"] --> FIN(["post-run: audit + seal + verify"])
```

Only `sandbox-tour` is sandboxed. The other three operate on the demo's own real run,
which is created and (by `close-run`) sealed like any ICM run. Stage 02 is sandboxed
because it deliberately TAMPERS frozen files, which must never hit the real run.

## What sandbox-tour proves (offline, no credentials)

`sandbox-tour` builds a throwaway run of this same skill and drives `icm.sh` through
every offline-checkable mechanic, capturing the real output:

```mermaid
flowchart TD
    A(["sandbox-tour"]) --> B["mktemp sandbox; export HOME + cd inside it (fully isolated)"]
    B --> C["icm.sh init: a throwaway frozen run of icm-demo"]
    C --> D["gate-check demo_publish while stage 01 active -> ALLOW (gate scoped to its own stage)"]
    D --> E["stage-done 01 -> stage 02 (the gated stage) becomes active"]
    E --> F["gate-check demo_publish, ready.md absent -> DENY (checker failed)"]
    F --> G["gate-check mcp__..__demo_publish -> DENY (mcp__ wrapper normalized, same gate matched)"]
    G --> H["gate-check Read -> ALLOW (gate names demo_publish, not Read)"]
    H --> I["write output/ready.md; gate-check demo_publish -> ALLOW"]
    I --> J["seal; verify-seal -> SEAL OK"]
    J --> K["edit events.jsonl; verify-seal -> SEAL MISMATCH (seal layer)"]
    K --> L["edit CONTEXT.md; gate-check -> DENY contract tampered (manifest layer)"]
    L --> M(["rm -rf sandbox (EXIT trap)"])
```

The stage-02 gate names a FABRICATED tool (`demo_publish`) that nothing actually calls,
so it is inert in a live run (it cannot deadlock the stage's own `Bash`); the tour
exercises it explicitly with `gate-check --tool demo_publish`.

## Edge cases specific to this skill

- **Audit shows one expected deviation without hooks.** A live run without
  `installer.sh --hooks` audits with exactly one "gates were ADVISORY ONLY" deviation.
  `close-run` detects and frames it; it is not a failure (enforcement is proven in the
  stage-02 sandbox). With hooks installed: zero deviations.
- **Sandbox token counts are null.** `sandbox-tour` and any no-transcript run show
  `counts: estimated`, `transcript_source: none`. Real four-field counts come from the
  demo's own live run, surfaced by `show-telemetry` and `close-run`'s audit.
- **No `ICM-CALL` here.** An execution spec requires a real tool call, which an offline
  demo never makes; hosting one would force a permanent audit deviation. See the working
  example in `cyril-antoni/publish-to-notion/stages/03-verify-share.md`.

For the runtime-wide edge cases (the two tamper layers, post-run sealing, transcript
resolution, gate scoping, cross-harness naming), see the ICM runtime README's
"Edge cases and gotchas" section, and `references/known-limits.md`.
