/**
 * pi extension: ICM stage-gate enforcement.
 *
 * Counterpart of gate-hook.sh for the pi coding agent. Subscribes to tool_call
 * (fired by the harness before any tool executes, outside the model's control)
 * and blocks the call while `icm.sh gate-check` denies it. Read-only: never
 * writes to the run dir.
 *
 * Install: symlinked into ~/.pi/agent/extensions/ by `installer.sh --hooks`,
 * or commit a copy to a workspace repo's .pi/extensions/.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
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

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event) => {
    // pi has no per-event cwd; the session's process cwd is the project dir.
    const cwd = process.cwd();
    if (!existsSync(join(cwd, ".icm"))) return undefined;

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
