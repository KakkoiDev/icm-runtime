/**
 * pi extension: ICM stage-gate enforcement.
 *
 * Counterpart of gate-hook.sh for the pi coding agent. Subscribes to tool_call
 * (fired by the harness before any tool executes, outside the model's control)
 * and blocks the call while `icm.sh gate-check` denies it. Never writes to run
 * dirs; records the active session transcript path into .icm/telemetry/ so
 * stage-done snapshots the right session (same mechanism as gate-hook.sh).
 *
 * Install: symlinked into ~/.pi/agent/extensions/ by `installer.sh --hooks`,
 * or commit a copy to a workspace repo's .pi/extensions/.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

function resolveIcmSh(): string | undefined {
  // Prefer icm.sh next to this file's real location (works for repo checkouts
  // and the ~/.agents symlink install); fall back to the canonical install path.
  const candidates: string[] = [];
  try {
    candidates.push(join(dirname(realpathSync(fileURLToPath(import.meta.url))), "icm.sh"));
  } catch {
    // import.meta.url may not resolve to a real file under some loaders
  }
  candidates.push(join(homedir(), ".agents", "skills", "icm", "runtime", "icm.sh"));
  return candidates.find((p) => existsSync(p));
}

// Record the newest session transcript under ~/.pi/agent/sessions into
// .icm/telemetry/transcript-path. During a live session the most recently
// written jsonl IS this session, which beats post-hoc guessing. Throttled to
// once a minute, best-effort: never interferes with gate evaluation.
function recordTranscriptPath(cwd: string) {
  try {
    const marker = join(cwd, ".icm", "telemetry", "transcript-path");
    try {
      if (Date.now() - statSync(marker).mtimeMs < 60_000) return;
    } catch {
      // marker missing: write it
    }
    let best: string | undefined;
    let bestM = 0;
    const walk = (d: string, depth: number) => {
      for (const e of readdirSync(d, { withFileTypes: true })) {
        const p = join(d, e.name);
        if (e.isDirectory() && depth > 0) walk(p, depth - 1);
        else if (e.isFile() && e.name.endsWith(".jsonl")) {
          const m = statSync(p).mtimeMs;
          if (m > bestM) {
            bestM = m;
            best = p;
          }
        }
      }
    };
    walk(join(homedir(), ".pi", "agent", "sessions"), 3);
    if (best) writeFileSync(marker, `${best}\n`);
  } catch {
    // best-effort only
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event) => {
    // pi has no per-event cwd; the session's process cwd is the project dir.
    const cwd = process.cwd();
    if (!existsSync(join(cwd, ".icm"))) return undefined;

    recordTranscriptPath(cwd);

    const icmSh = resolveIcmSh();
    if (!icmSh) {
      // Fail closed: missing runtime must not become missing enforcement.
      return { block: true, reason: "icm gate: icm.sh not found, cannot evaluate gates. Reinstall icm-runtime or remove this extension." };
    }

    try {
      execFileSync(icmSh, ["gate-check", "--tool", event.toolName, "--cwd", cwd], {
        encoding: "utf8",
        timeout: 15000,
      });
      return undefined;
    } catch (e: any) {
      const out = `${e.stdout ?? ""}${e.stderr ?? ""}`.trim();
      const reason = out.split("\n").slice(0, 10).join("\n") || `icm gate: gate-check failed (${e.message ?? "unknown error"})`;
      return { block: true, reason };
    }
  });
}
