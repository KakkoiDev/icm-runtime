"""Run pr-agent's own CLI with every LLM call served by `claude -p`.

Run with pr-agent's interpreter; the arguments are pr-agent CLI arguments, e.g.
    <pr-agent-python> pr-agent-claude.py --diff-file pr.diff --output out.md review

pr-agent's PRAgent takes an `ai_handler` factory and passes it to every tool. This script
binds that factory to ClaudeCLIHandler and then runs pr-agent's unmodified `cli.run()`, so
diff processing, prompts, YAML parsing and markdown rendering are pr-agent's; only the model
transport differs. The handler runs the official `claude` CLI in print mode on the user's
own login: no API key, no token handling, no tools, no MCP, no settings or hooks loaded.
"""
import asyncio
import functools
import json
import os
import sys
import tempfile

import pr_agent.cli as cli
from pr_agent.agent.pr_agent import PRAgent
from pr_agent.algo.ai_handlers.base_ai_handler import BaseAiHandler

CLAUDE_MODEL = "claude-opus-5-5"
TIMEOUT_SECONDS = 900


def claude_argv(system_prompt_file: str) -> list[str]:
    return [
        "claude", "-p",
        "--model", CLAUDE_MODEL,
        "--system-prompt-file", system_prompt_file,
        "--tools", "",
        "--setting-sources", "",
        "--strict-mcp-config",
        "--disable-slash-commands",
        "--no-session-persistence",
        "--output-format", "json",
    ]


def parse_result(stdout: bytes, returncode: int) -> tuple[str, str]:
    """Map `claude -p --output-format json` to pr-agent's (response, finish_reason)."""
    try:
        data = json.loads(stdout)
    except ValueError as e:
        raise RuntimeError(f"claude -p exited {returncode} with non-JSON output: {stdout[:300]!r}") from e
    if returncode != 0 or data.get("is_error") or data.get("subtype") != "success":
        raise RuntimeError(f"claude -p failed (exit {returncode}): {str(data.get('result'))[:300]}")
    finish_reason = "length" if data.get("stop_reason") == "max_tokens" else "stop"
    return data["result"], finish_reason


class ClaudeCLIHandler(BaseAiHandler):
    def __init__(self):
        pass

    @property
    def deployment_id(self):
        return None

    async def chat_completion(self, model: str, system: str, user: str, temperature: float = 0.2, img_path: str = None):
        messages = self.build_request_messages(model, system, user)
        with tempfile.TemporaryDirectory() as work:
            system_file = os.path.join(work, "system.txt")
            with open(system_file, "w", encoding="utf-8") as fh:
                fh.write(messages[0]["content"])
            proc = await asyncio.create_subprocess_exec(
                *claude_argv(system_file),
                cwd=work,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            try:
                stdout, stderr = await asyncio.wait_for(
                    proc.communicate(messages[1]["content"].encode("utf-8")), TIMEOUT_SECONDS
                )
            except asyncio.TimeoutError:
                proc.kill()
                await proc.wait()
                raise RuntimeError(f"claude -p timed out after {TIMEOUT_SECONDS}s")
        return parse_result(stdout, proc.returncode)


if __name__ == "__main__":
    cli.PRAgent = functools.partial(PRAgent, ai_handler=ClaudeCLIHandler)
    sys.exit(cli.run())
