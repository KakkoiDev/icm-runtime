/**
 * Drives the icm-gate pi extension without pi: loads the module given as
 * argv[1], registers a fake ExtensionAPI, fires one tool_call for the tool
 * named by argv[2], and prints the handler's decision as JSON (null = allow).
 * Run with cwd = the project dir under test.
 */
import { pathToFileURL } from "node:url";

const mod = await import(pathToFileURL(process.argv[2]).href);
let handler: any;
const fakePi = {
  on: (event: string, h: any) => {
    if (event === "tool_call") handler = h;
  },
};
mod.default(fakePi);
if (!handler) {
  console.error("extension did not subscribe to tool_call");
  process.exit(2);
}
const res = await handler({ toolName: process.argv[3] }, {});
console.log(JSON.stringify(res ?? null));
