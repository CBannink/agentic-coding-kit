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

// Run a PreTool/PostTool hook script via stdin JSON contract.
// Mirrors how Claude Code's PreToolUse/PostToolUse hooks work:
// the script reads the payload from stdin, decides allow/block via
// exit code (2 = block, 0 = allow), reason on stderr.
function runHookScript(hookScript: string, payload: any): { exitCode: number; stderr: string } {
  const path = join(TOOLS, "hooks", hookScript);
  if (!existsSync(path)) {
    return { exitCode: 0, stderr: "" }; // missing hook = no-op (graceful)
  }
  const json = JSON.stringify(payload);
  const result = spawnSync(SHELL, ["-NoProfile", "-File", path], {
    input: json,
    encoding: "utf-8",
    shell: false,
    timeout: 30_000,
  });
  return {
    exitCode: result.status ?? 0,
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

    // tool.execute.before -- the protocol-layer enforcement entry point.
    // Mirrors Claude Code's PreToolUse hooks. Routes to the appropriate
    // PreTool hook script based on the tool name, then translates the
    // script's exit code 2 into OpenCode's `output.abort` to actually
    // block the tool call. Missing hooks = no-op (graceful).
    "tool.execute.before": async (input: any, output: any) => {
      const toolName = String(input?.tool ?? "").toLowerCase();
      const sessionId = input?.session?.id || "unknown";
      // Build a Claude-Code-style payload so the PowerShell hook scripts
      // (which already work for Claude Code) parse the same JSON shape.
      const payload = {
        session_id: sessionId,
        tool_name: input?.tool,
        tool_input: input?.args ?? input?.input ?? {},
        hook_event_name: "PreToolUse",
      };
      let hookScript: string | null = null;
      if (toolName === "bash" || toolName.includes("shell") || toolName.includes("execute")) {
        hookScript = "pretool-bash-dispatcher.ps1";
      } else if (toolName === "write" || toolName === "edit" || toolName.includes("write") || toolName.includes("edit")) {
        hookScript = "pretool-write-gateguard.ps1";
      } else if (toolName === "task" || toolName.includes("agent") || toolName.includes("subagent") || toolName.includes("spawn")) {
        hookScript = "pretool-task-orchestrator-gate.ps1";
      }
      if (!hookScript) return;
      const { exitCode, stderr } = runHookScript(hookScript, payload);
      if (exitCode === 2) {
        // Block the tool call. OpenCode plugin contract: throw to abort,
        // OR set output.abort if available. Throw is most reliable.
        const reason = stderr.trim() || "Blocked by kit hook";
        if (output && typeof output === "object") {
          output.abort = reason;
        }
        throw new Error(reason);
      }
      // Surface stderr as a soft warning (PreToolUse exit 0 with stderr
      // is the "info-only" pattern -- write-gateguard uses it for the
      // first-edit reminder). OpenCode logs plugin stderr to its own
      // event stream so the agent can see it.
      if (stderr && stderr.trim()) {
        // eslint-disable-next-line no-console
        console.error(stderr.trim());
      }
    },

    // tool.execute.after -- mirrors PostToolUse hook. Currently used by
    // the verify-auto-mark hook to mark verification_evidence after a
    // successful test command (closes the Iron Law loop without agent
    // thought).
    "tool.execute.after": async (input: any, output: any) => {
      const toolName = String(input?.tool ?? "").toLowerCase();
      if (toolName !== "bash" && !toolName.includes("shell") && !toolName.includes("execute")) {
        return; // only PostBash needed for verify-auto-mark
      }
      const sessionId = input?.session?.id || "unknown";
      // Translate OpenCode's output shape to Claude's tool_response.exit_code
      // so the PowerShell hook script (which expects Claude's contract) works.
      const exitCode =
        output?.exit_code ??
        output?.exitCode ??
        output?.result?.exit_code ??
        output?.result?.exitCode ??
        (output?.error ? 1 : 0);
      const payload = {
        session_id: sessionId,
        tool_name: input?.tool,
        tool_input: input?.args ?? input?.input ?? {},
        tool_response: { exit_code: exitCode },
        hook_event_name: "PostToolUse",
      };
      const { stderr } = runHookScript("posttool-bash-verify-mark.ps1", payload);
      if (stderr && stderr.trim()) {
        // eslint-disable-next-line no-console
        console.error(stderr.trim());
      }
    },

    // session.compacted = pre-compact event; capture compact brief
    "session.compacted": async (input: any, _output: any) => {
      const sessionId = input?.session?.id || "unknown";
      runScript("precompact-hook.ps1", ["-SessionId", sessionId]);
    },
  };
};

export default AgenticKit;
