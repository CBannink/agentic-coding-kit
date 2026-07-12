import { exec as execCallback, execFile as execFileCallback } from "node:child_process";
import { createHash } from "node:crypto";
import { lstat, readFile, readdir } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { parseJsonc, parseToml } from "./parsers.js";
import { BLOCK_END, BLOCK_START } from "./managed-block.js";
import { resolveHostPaths, type InstallScope, type PathEnvironment } from "./host-paths.js";
import type { Host } from "./types.js";

const execFile = promisify(execFileCallback);
const exec = promisify(execCallback);

interface ManifestFile { path: string; sha256: string; sourceId: string }
interface DoctorManifest { files: ManifestFile[]; managedBlocks: Array<{ path: string; id?: string; format?: "markdown" | "toml" }>; securityProfile: string; memoryProfile: string }
export interface DoctorReport { host: Host; platform: string; architecture: string; version?: string; resolved: Record<string, string | undefined>; errors: string[]; warnings: string[]; profiles: Record<string, string> }

export async function doctorHost(host: Host, scope: InstallScope, repo?: string, context?: PathEnvironment, sourceRoot = process.cwd()): Promise<DoctorReport> {
  const paths = await resolveHostPaths(host, scope, repo, context);
  const errors: string[] = [];
  const warnings: string[] = [];
  let version: string | undefined;
  try { version = await detectHostVersion(host); }
  catch { warnings.push(`${host} CLI is missing or unavailable`); }
  const manifestPath = path.join(paths.administrationRoot, `install-${host}-${scope}.json`);
  let manifest: DoctorManifest | undefined;
  try { manifest = JSON.parse(await readFile(manifestPath, "utf8")) as DoctorManifest; }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") warnings.push("Managed installation manifest is missing"); else errors.push("Managed installation manifest is malformed"); }
  for (const file of manifest?.files ?? []) {
    try {
      const content = await readFile(file.path, "utf8");
      if (content.charCodeAt(0) === 0xfeff) errors.push(`UTF-8 BOM: ${file.path}`);
      if (sha256(content) !== file.sha256) {
        if (isLocalCodexModelOverride(file.path, content)) warnings.push(`Local Codex model override: ${file.path}`);
        else errors.push(`Managed hash conflict: ${file.path}`);
      }
      if (/gpt-5\.4/i.test(content)) errors.push(`Stale GPT-5.4 reference: ${file.path}`);
    } catch { errors.push(`Missing managed file: ${file.path}`); }
  }
  for (const block of manifest?.managedBlocks ?? []) {
    try {
      const content = await readFile(block.path, "utf8");
      if (block.format === "toml") {
        if (count(content, "# agentic-coding-kit:start") !== 1 || count(content, "# agentic-coding-kit:end") !== 1) errors.push(`Managed block broken: ${block.path}`);
      } else if (count(content, BLOCK_START) !== 1 || count(content, BLOCK_END) !== 1) errors.push(`Managed block broken: ${block.path}`);
    } catch { errors.push(`Managed block file missing: ${block.path}`); }
  }
  if (paths.config) {
    try {
      const config = await readFile(paths.config, "utf8");
      if (host === "codex") parseToml(config); else parseJsonc(config);
      if (/gpt-5\.4/i.test(config)) errors.push(`Stale GPT-5.4 reference: ${paths.config}`);
    } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") errors.push(`Malformed host configuration: ${paths.config}`); }
  }
  const skillRoots = discoverySkillRoots(host, scope, paths.root, paths.skills, context?.home ?? os.homedir());
  const occurrences = new Map<string, string[]>();
  for (const root of skillRoots) {
    try {
      for (const entry of await readdir(root, { withFileTypes: true })) if (entry.isDirectory()) {
        const list = occurrences.get(entry.name) ?? [];
        list.push(root);
        occurrences.set(entry.name, list);
      }
    } catch { /* optional discovery root */ }
  }
  for (const [id, roots] of occurrences) if (roots.length > 1) warnings.push(`Duplicate skill ${id}: ${roots.join(", ")}`);
  if (scope === "project") {
    try { await readFile(path.join(paths.root, ".wiki", "index.md"), "utf8"); } catch { warnings.push("Repository .wiki/index.md is missing"); }
  }
  for (const launcher of ["install.sh", "install-codex.sh", "install-claude.sh", "install-opencode.sh", "install-copilot.sh", "install-all.sh"]) {
    try { const stat = await lstat(path.join(sourceRoot, "scripts", launcher)); if (process.platform !== "win32" && !(stat.mode & 0o111)) errors.push(`Launcher is not executable: scripts/${launcher}`); } catch { warnings.push(`Launcher missing: scripts/${launcher}`); }
  }
  return { host, platform: os.platform(), architecture: os.arch(), version, resolved: { instruction: paths.instruction, agents: paths.agents, skills: paths.skills, commands: paths.commands, config: paths.config, manifest: manifestPath }, errors, warnings, profiles: { model: "preserved by kit", security: manifest?.securityProfile ?? "unknown", memory: manifest?.memoryProfile ?? "unknown" } };
}

async function detectHostVersion(host: Host): Promise<string> {
  if (process.platform === "win32") {
    const located = (await execFile("where.exe", [host], { encoding: "utf8", timeout: 5000 })).stdout
      .split(/\r?\n/).map((entry) => entry.trim()).filter(Boolean);
    const executable = located.find((entry) => entry.toLowerCase().endsWith(".exe")) ?? located[0];
    if (!executable) throw new Error(`${host} was not found on PATH`);
    if (executable.toLowerCase().endsWith(".exe")) return (await execFile(executable, ["--version"], { encoding: "utf8", timeout: 5000 })).stdout.trim();
    const command = `"${executable.replaceAll('"', '""')}" --version`;
    return (await exec(command, { encoding: "utf8", timeout: 5000, windowsHide: true })).stdout.trim();
  }
  return (await execFile(host, ["--version"], { encoding: "utf8", timeout: 5000 })).stdout.trim();
}

function discoverySkillRoots(host: Host, scope: InstallScope, root: string, native: string, home: string): string[] {
  if (scope === "user") {
    if (host === "opencode") {
      return [native, path.join(home, ".claude", "skills"), path.join(home, ".agents", "skills")];
    }
    if (host === "copilot") {
      return [native, path.join(home, ".agents", "skills")];
    }
    return [native];
  }
  if (host === "opencode") return [native, path.join(root, ".claude", "skills"), path.join(root, ".agents", "skills")];
  if (host === "copilot") return [native, path.join(root, ".claude", "skills"), path.join(root, ".agents", "skills")];
  return [native];
}
function count(value: string, needle: string): number { return value.split(needle).length - 1; }
function sha256(value: string): string { return createHash("sha256").update(value, "utf8").digest("hex"); }
function isLocalCodexModelOverride(filePath: string, content: string): boolean {
  return filePath.endsWith(".toml") && /^model = "[^"]+"\r?\nmodel_reasoning_effort = "[^"]+"\r?\n?$/m.test(content);
}
