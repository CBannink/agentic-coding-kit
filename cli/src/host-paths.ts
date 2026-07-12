import { execFile as execFileCallback } from "node:child_process";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import type { Host } from "./types.js";

const execFile = promisify(execFileCallback);
export type InstallScope = "user" | "project";

export interface PathEnvironment {
  home: string;
  platform: NodeJS.Platform;
  env: NodeJS.ProcessEnv;
}

export interface HostPaths {
  host: Host;
  scope: InstallScope;
  root: string;
  administrationRoot: string;
  instruction: string;
  hostInstruction?: string;
  agents: string;
  skills: string;
  commands?: string;
  config?: string;
  localSettings?: string;
}

export function currentPathEnvironment(): PathEnvironment {
  return { home: os.homedir(), platform: process.platform, env: process.env };
}

export async function resolveProjectRoot(candidate: string): Promise<string> {
  const resolved = path.resolve(candidate);
  const { stdout } = await execFile("git", ["-C", resolved, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  return path.resolve(stdout.trim());
}

export async function resolveHostPaths(host: Host, scope: InstallScope, repo: string | undefined, context = currentPathEnvironment()): Promise<HostPaths> {
  const projectRoot = scope === "project" ? await resolveProjectRoot(repo ?? process.cwd()) : undefined;
  const home = path.resolve(context.home);
  if (host === "codex") {
    const codexHome = path.resolve(context.env.CODEX_HOME || path.join(home, ".codex"));
    return scope === "user"
      ? { host, scope, root: home, administrationRoot: path.join(codexHome, ".agentic-kit"), instruction: path.join(codexHome, "AGENTS.md"), agents: path.join(codexHome, "agents"), skills: path.join(home, ".agents", "skills"), config: path.join(codexHome, "config.toml") }
      : { host, scope, root: projectRoot!, administrationRoot: path.join(projectRoot!, ".git", "agentic-kit"), instruction: path.join(projectRoot!, "AGENTS.md"), agents: path.join(projectRoot!, ".codex", "agents"), skills: path.join(projectRoot!, ".agents", "skills"), config: path.join(projectRoot!, ".codex", "config.toml") };
  }
  if (host === "claude") {
    const claudeHome = path.resolve(context.env.CLAUDE_CONFIG_DIR || path.join(home, ".claude"));
    if (scope === "user") return { host, scope, root: claudeHome, administrationRoot: path.join(claudeHome, ".agentic-kit"), instruction: path.join(claudeHome, "CLAUDE.md"), agents: path.join(claudeHome, "agents"), skills: path.join(claudeHome, "skills"), config: path.join(claudeHome, "settings.json") };
    const instruction = await chooseClaudeInstruction(projectRoot!);
    return { host, scope, root: projectRoot!, administrationRoot: path.join(projectRoot!, ".git", "agentic-kit"), instruction, agents: path.join(projectRoot!, ".claude", "agents"), skills: path.join(projectRoot!, ".claude", "skills"), config: path.join(projectRoot!, ".claude", "settings.json"), localSettings: path.join(projectRoot!, ".claude", "settings.local.json") };
  }
  if (host === "opencode") {
    const configRoot = path.resolve(context.env.OPENCODE_CONFIG_DIR || path.join(home, ".config", "opencode"));
    const configuredFile = context.env.OPENCODE_CONFIG ? path.resolve(context.env.OPENCODE_CONFIG) : undefined;
    const userConfig = configuredFile ?? await firstExisting([
      path.join(configRoot, "opencode.json"),
      path.join(configRoot, "opencode.jsonc"),
    ]) ?? path.join(configRoot, "opencode.json");
    return scope === "user"
      ? { host, scope, root: configRoot, administrationRoot: path.join(configRoot, ".agentic-kit"), instruction: path.join(configRoot, "AGENTS.md"), agents: path.join(configRoot, "agents"), skills: path.join(configRoot, "skills"), commands: path.join(configRoot, "commands"), config: userConfig }
      : { host, scope, root: projectRoot!, administrationRoot: path.join(projectRoot!, ".git", "agentic-kit"), instruction: path.join(projectRoot!, "AGENTS.md"), agents: path.join(projectRoot!, ".opencode", "agents"), skills: path.join(projectRoot!, ".opencode", "skills"), commands: path.join(projectRoot!, ".opencode", "commands"), config: path.join(projectRoot!, "opencode.json") };
  }
  const copilotHome = path.resolve(context.env.COPILOT_HOME || path.join(home, ".copilot"));
  return scope === "user"
    ? { host, scope, root: copilotHome, administrationRoot: path.join(copilotHome, ".agentic-kit"), instruction: path.join(copilotHome, "copilot-instructions.md"), agents: path.join(copilotHome, "agents"), skills: path.join(copilotHome, "skills"), config: path.join(copilotHome, "settings.json") }
    : { host, scope, root: projectRoot!, administrationRoot: path.join(projectRoot!, ".git", "agentic-kit"), instruction: path.join(projectRoot!, "AGENTS.md"), hostInstruction: path.join(projectRoot!, ".github", "copilot-instructions.md"), agents: path.join(projectRoot!, ".github", "agents"), skills: path.join(projectRoot!, ".github", "skills") };
}

async function firstExisting(candidates: string[]): Promise<string | undefined> {
  const { access } = await import("node:fs/promises");
  for (const candidate of candidates) {
    try { await access(candidate); return candidate; } catch { /* continue */ }
  }
  return undefined;
}

async function chooseClaudeInstruction(repo: string): Promise<string> {
  const root = path.join(repo, "CLAUDE.md");
  const nested = path.join(repo, ".claude", "CLAUDE.md");
  const { access } = await import("node:fs/promises");
  try { await access(root); return root; } catch { /* continue */ }
  try { await access(nested); return nested; } catch { return root; }
}
