// agentic-kit.ts — OpenCode lifecycle plugin for the Caspar Bannink Agentic
// Coding Kit. Uses OpenCode's actual plugin API (verified against
// https://opencode.ai/docs/plugins/): exports an async function that
// receives context and returns an event handler object keyed by event name.
//
// Wires the kit's pre-session.ps1 / post-session.ps1 / subagent-stop scripts
// into OpenCode's lifecycle so the self-improvement loop runs automatically.

import type { Plugin } from "@opencode-ai/plugin";
import { spawnSync } from "node:child_process";
import { homedir } from "node:os";
import { existsSync } from "node:fs";
import { join } from "node:path";

const TOOLS = process.env.AGENTS_HOME
  ? join(process.env.AGENTS_HOME, "tools")
  : join(homedir(), ".agents", "tools");

// Resolve PowerShell host: prefer pwsh, fall back to Windows PowerShell.
function resolveShell(): string {
  // Try pwsh first
  const probe = spawnSync("pwsh", ["-NoProfile", "-Command", "exit 0"], {
    encoding: "utf-8",
    shell: true,
  });
  if (probe.status === 0) return "pwsh";
  return "powershell";
}
const SHELL = resolveShell();

function runScript(script: string, args: string[]): { ok: boolean; stdout: string; stderr: string } {
  const path = join(TOOLS, script);
  if (!existsSync(path)) {
    return { ok: false, stdout: "", stderr: `tool not found: ${path}` };
  }
  const result = spawnSync(SHELL, ["-NoProfile", "-File", path, ...args], {
    encoding: "utf-8",
    shell: false,
    timeout: 60_000,
  });
  return {
    ok: result.status === 0,
    stdout: result.stdout ?? "",
    stderr: result.stderr ?? "",
  };
}

export const AgenticKit: Plugin = async ({ project, client, $, directory, worktree }) => {
  return {
    // session.created fires when a new session begins
    "session.created": async (input: any, _output: any) => {
      const sessionId = input?.session?.id || `oc-${Date.now()}`;
      const task = input?.session?.title || input?.title || "opencode session";
      runScript("session-start-hook.ps1", [
        "-SessionId", sessionId,
        "-Mode", "build",
        "-Task", task,
        "-RepoRoot", directory ?? process.cwd(),
      ]);
    },

    // session.error captures runtime failures so the reflection loop can pick them up
    "session.error": async (input: any, _output: any) => {
      const sessionId = input?.session?.id || "unknown";
      const errMsg = input?.error?.message ?? input?.message ?? "session error";
      runScript("session-end-hook.ps1", [
        "-SessionId", sessionId,
        "-Outcome", "error",
        "-Summary", errMsg.slice(0, 200),
      ]);
    },

    // session.deleted is the canonical "session is over" signal -- fire post-session
    "session.deleted": async (input: any, _output: any) => {
      const sessionId = input?.session?.id || "unknown";
      runScript("session-end-hook.ps1", [
        "-SessionId", sessionId,
        "-Outcome", "session-end",
      ]);
      // post-session is the heavy lifter: registers handoff, runs auto-consolidate,
      // compress-memory, harness-propose, reflect-trigger gate.
      runScript("post-session.ps1", [
        "-SessionId", sessionId,
        "-NonInteractive",
        "-AutoApprove",
      ]);
    },

    // tool.execute.before lets us register subagent invocations as they happen
    "tool.execute.before": async (input: any, _output: any) => {
      // Only register noteworthy tool calls (avoid noise from every read/grep)
      const toolName = input?.tool ?? "";
      const subagentLike = ["task", "agent", "subagent", "spawn"];
      if (!subagentLike.some((s) => toolName.toLowerCase().includes(s))) return;
      const sessionId = input?.session?.id || "unknown";
      runScript("subagent-stop-hook.ps1", [
        "-SessionId", sessionId,
        "-AgentName", toolName,
        "-Status", "registered",
      ]);
    },

    // session.compacted = pre-compact event; capture compact brief
    "session.compacted": async (input: any, _output: any) => {
      const sessionId = input?.session?.id || "unknown";
      runScript("precompact-hook.ps1", ["-SessionId", sessionId]);
    },
  };
};

export default AgenticKit;
