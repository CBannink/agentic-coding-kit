import { createHash } from "node:crypto";
import { access, cp, lstat, mkdir, readFile, readdir, rm, unlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { atomicWriteContained, unlinkContained } from "./paths.js";
import { mergeManagedBlock, removeManagedBlock } from "./managed-block.js";
import { getJsoncValue, mergeTomlManagedBlock, removeTomlManagedBlock, setJsoncValue } from "./config-merge.js";
import { loadManifest } from "./manifest.js";
import { renderArtifacts, GENERATED_MARKER } from "./render.js";
import { resolveHostPaths, type HostPaths, type InstallScope, type PathEnvironment } from "./host-paths.js";
import type { GeneratedFile, Host, InstallProfile } from "./types.js";

export type SecurityProfile = "preserve" | "guarded" | "permissive";
export type MemoryProfile = "preserve" | "wiki-only";
export type CommandsMode = "auto" | "on" | "off";

export interface InstallOptions {
  repoRoot: string;
  host: Host;
  scope: InstallScope;
  repo?: string;
  profile: InstallProfile;
  security: SecurityProfile;
  memory: MemoryProfile;
  commands: CommandsMode;
  setDefaultAgent: boolean;
  dryRun: boolean;
  force: boolean;
  yes: boolean;
  verbose: boolean;
  clearGlobalConfig?: boolean;
  pathContext?: PathEnvironment;
}

interface ManagedFile { path: string; sha256: string; ownership: "managed"; sourceId: string }
interface ManagedBlock { path: string; id: string; bodyHash: string; format: "markdown" | "toml" }
interface ConfigChange { path: string; keyPath: (string | number)[]; value: unknown; previousExists: boolean; previousValue: unknown }
interface ManagedLine { path: string; line: string }
export interface InstallManifest {
  schemaVersion: 1; kitVersion: string; host: Host; scope: InstallScope; root: string;
  files: ManagedFile[]; managedBlocks: ManagedBlock[]; configChanges: ConfigChange[];
  managedLines: ManagedLine[];
  securityProfile: SecurityProfile; memoryProfile: MemoryProfile;
}
export interface InstallResult { host: Host; scope: InstallScope; actions: string[]; warnings: string[]; manifestPath: string }

export const GLOBAL_RESET_WARNING = `DESTRUCTIVE GLOBAL INSTALL

--clear-global-config backs up and then replaces the selected harness's global
instructions, agents, skills, commands, and primary settings/config file.
Authentication credentials and opaque application state are not removed.`;

export async function installHost(options: InstallOptions): Promise<InstallResult> {
  if (options.security === "permissive" && !options.yes) throw new Error("PERMISSIVE AGENT PROFILE requires --security permissive --yes");
  if (options.clearGlobalConfig && options.scope !== "user") throw new Error("--clear-global-config is available only with --scope user");
  if (options.clearGlobalConfig && !options.yes) throw new Error("--clear-global-config requires --yes after reading the destructive-install warning");
  const paths = await resolveHostPaths(options.host, options.scope, options.repo, options.pathContext);
  const actions: string[] = [];
  if (options.clearGlobalConfig) await resetGlobalConfig(paths, options, actions);
  const manifestPath = installManifestPath(paths);
  const previous = options.clearGlobalConfig ? undefined : await readInstallManifest(manifestPath);
  const canonical = await loadManifest(options.repoRoot);
  const commands = options.commands === "on" || (options.commands === "auto" && options.host === "opencode");
  const rendered = await renderArtifacts(options.repoRoot, canonical, { installProfile: options.profile, commands });
  const desired = mapRenderedFiles(rendered, paths);
  const orchestrator = await readFile(path.join(options.repoRoot, canonical.instruction_fragments.orchestrator), "utf8");
  const warnings: string[] = [];
  const files: ManagedFile[] = [];
  const blocks: ManagedBlock[] = [];
  const configChanges: ConfigChange[] = [];
  const managedLines: ManagedLine[] = [];

  for (const file of desired) {
    const installedContent = await planAndWriteFile(file.target, file.content, file.sourceId, previous?.files.find((item) => samePath(item.path, file.target)), options, actions);
    files.push({ path: file.target, sha256: sha256(installedContent), ownership: "managed", sourceId: file.sourceId });
  }
  const desiredTargets = new Set(files.map((file) => path.resolve(file.path).toLowerCase()));
  for (const stale of previous?.files ?? []) {
    if (desiredTargets.has(path.resolve(stale.path).toLowerCase())) continue;
    let current: string;
    try { current = await readFile(stale.path, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") continue; throw error; }
    if (sha256(current) !== stale.sha256) {
      if (!options.force) throw new Error(`Locally modified stale managed file conflict: ${stale.path}`);
      await backupFile(stale.path, current, options.dryRun, actions);
    }
    if (!options.dryRun) await unlinkContained(path.dirname(stale.path), path.basename(stale.path), "managed file directory");
    actions.push(`${options.dryRun ? "PLAN REMOVE" : "REMOVE"} ${stale.path}`);
  }

  const instructionBody = `${orchestrator.trim()}\n\n${invocationNote(options.host)}`;
  await planAndMergeBlock(paths.instruction, instructionBody, "agentic-coding-kit", "markdown", options, actions);
  blocks.push({ path: paths.instruction, id: "agentic-coding-kit", bodyHash: sha256(instructionBody), format: "markdown" });
  if (paths.hostInstruction) {
    const hostBody = "For GitHub Copilot CLI, request kit skills in natural language, inspect available skills with `/skills`, and select custom agents with `/agent` or supported `--agent` invocation. Shared orchestration rules are owned by the root `AGENTS.md` block.";
    await planAndMergeBlock(paths.hostInstruction, hostBody, "agentic-coding-kit-copilot", "markdown", options, actions);
    blocks.push({ path: paths.hostInstruction, id: "agentic-coding-kit-copilot", bodyHash: sha256(hostBody), format: "markdown" });
  }

  if (options.host === "codex" && paths.config && options.security !== "preserve") {
    const body = codexSecurityBody(options.security);
    await planAndMergeBlock(paths.config, body, "agentic-coding-kit-profile", "toml", options, actions);
    blocks.push({ path: paths.config, id: "agentic-coding-kit-profile", bodyHash: sha256(body), format: "toml" });
  } else if (options.security !== "preserve") warnings.push(`${options.host} security profile preserved: no validated managed setting is emitted for this host`);

  if (options.host === "claude" && options.scope === "project" && options.memory === "wiki-only" && paths.localSettings) {
    const change = carryOriginalChange(await planJsoncChange(paths.localSettings, ["autoMemoryEnabled"], false, options, actions), previous);
    configChanges.push(change);
    if (await ensureGitignoreLine(paths.root, ".claude/settings.local.json", options, actions)) managedLines.push({ path: path.join(paths.root, ".gitignore"), line: ".claude/settings.local.json" });
  } else if (options.memory === "wiki-only" && options.host !== "claude") warnings.push(`${options.host} has no managed auto-memory setting; preserved`);

  if (options.host === "opencode" && options.setDefaultAgent && paths.config) {
    const primary = primaryOpenCodeFile(paths, orchestrator);
    await planAndWriteFile(primary.target, primary.content, primary.sourceId, previous?.files.find((item) => samePath(item.path, primary.target)), options, actions);
    files.push({ path: primary.target, sha256: sha256(primary.content), ownership: "managed", sourceId: primary.sourceId });
    configChanges.push(carryOriginalChange(await planJsoncChange(paths.config, ["default_agent"], "agentic-kit", options, actions), previous));
  }

  const output: InstallManifest = { schemaVersion: 1, kitVersion: canonical.kit_version, host: options.host, scope: options.scope, root: paths.root, files, managedBlocks: blocks, configChanges, managedLines, securityProfile: options.security, memoryProfile: options.memory };
  if (!options.dryRun) await writeAbsoluteAtomic(manifestPath, `${JSON.stringify(output, null, 2)}\n`);
  actions.push(`${options.dryRun ? "PLAN" : "WRITE"} ${manifestPath}`);
  return { host: options.host, scope: options.scope, actions, warnings, manifestPath };
}

export async function uninstallHost(options: Pick<InstallOptions, "host" | "scope" | "repo" | "dryRun" | "force" | "repoRoot" | "pathContext">): Promise<InstallResult> {
  const paths = await resolveHostPaths(options.host, options.scope, options.repo, options.pathContext);
  const manifestPath = installManifestPath(paths);
  const manifest = await readInstallManifest(manifestPath);
  if (!manifest) return { host: options.host, scope: options.scope, actions: ["NOT INSTALLED"], warnings: [], manifestPath };
  const actions: string[] = [];
  for (const file of manifest.files) {
    try {
      const current = await readFile(file.path, "utf8");
      if (sha256(current) !== file.sha256) {
        if (!options.force) throw new Error(`Locally modified managed file conflict: ${file.path}`);
        await backupFile(file.path, current, options.dryRun, actions);
      }
      if (!options.dryRun) await unlinkContained(path.dirname(file.path), path.basename(file.path), "managed file directory");
      actions.push(`${options.dryRun ? "PLAN REMOVE" : "REMOVE"} ${file.path}`);
    } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  for (const block of manifest.managedBlocks) {
    if (await anotherInstallOwnsBlock(paths, manifestPath, block.path)) continue;
    let current: string;
    try { current = await readFile(block.path, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") continue; throw error; }
    const next = block.format === "toml" ? removeTomlManagedBlock(current, options.force) : removeManagedBlock(current, options.force);
    if (!options.dryRun) await writeAbsoluteAtomic(block.path, next);
    actions.push(`${options.dryRun ? "PLAN BLOCK REMOVE" : "BLOCK REMOVE"} ${block.path}`);
  }
  for (const change of manifest.configChanges) await restoreJsoncChange(change, options.dryRun, actions);
  for (const managedLine of manifest.managedLines ?? []) await removeManagedLine(managedLine, options.dryRun, actions);
  if (!options.dryRun) await unlink(manifestPath);
  actions.push(`${options.dryRun ? "PLAN REMOVE" : "REMOVE"} ${manifestPath}`);
  return { host: options.host, scope: options.scope, actions, warnings: [], manifestPath };
}

function mapRenderedFiles(files: GeneratedFile[], paths: HostPaths): Array<{ target: string; content: string; sourceId: string }> {
  const prefix = `adapters/${paths.host}/`;
  return files.flatMap((file) => {
    if (!file.path.startsWith(prefix) || file.path.endsWith("instructions.md") || file.path.endsWith(".agentic-kit-generated.json")) return [];
    const relative = file.path.slice(prefix.length);
    if (relative.startsWith("agents/")) return [{ target: path.join(paths.agents, path.basename(relative)), content: file.content, sourceId: file.sourceId }];
    if (relative.startsWith("skills/")) return [{ target: path.join(paths.skills, relative.slice("skills/".length)), content: file.content, sourceId: file.sourceId }];
    if (relative.startsWith("commands/") && paths.commands) return [{ target: path.join(paths.commands, path.basename(relative)), content: file.content, sourceId: file.sourceId }];
    return [];
  });
}

async function planAndWriteFile(target: string, content: string, sourceId: string, previous: ManagedFile | undefined, options: Pick<InstallOptions, "force" | "dryRun" | "clearGlobalConfig">, actions: string[]): Promise<string> {
  let existing: string | undefined;
  if (!(options.clearGlobalConfig && options.dryRun)) {
    try { existing = await readFile(target, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  const effectiveContent = existing ? preserveLocalCodexModelOverride(target, existing, content, previous) : content;
  if (existing !== undefined && existing !== effectiveContent) {
    const trusted = previous && previous.sourceId === sourceId && sha256(existing) === previous.sha256 && hasGeneratedHeader(existing, sourceId);
    const legacyKitOwned = !previous && isLegacyKitOwned(existing);
    if (!trusted && !legacyKitOwned && !options.force) throw new Error(`Managed file conflict: ${target}`);
    if (!trusted && (legacyKitOwned || options.force)) await backupFile(target, existing, options.dryRun, actions);
  }
  if (!options.dryRun && existing !== effectiveContent) await writeAbsoluteAtomic(target, effectiveContent);
  actions.push(`${options.dryRun ? "PLAN WRITE" : existing === effectiveContent ? "UNCHANGED" : "WRITE"} ${target}`);
  return effectiveContent;
}

async function planAndMergeBlock(target: string, body: string, id: string, format: "markdown" | "toml", options: Pick<InstallOptions, "force" | "dryRun" | "clearGlobalConfig">, actions: string[]): Promise<void> {
  let existing = "";
  if (!(options.clearGlobalConfig && options.dryRun)) {
    try { existing = await readFile(target, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  if (options.force && existing && isAmbiguousManagedBlock(existing, format)) await backupFile(target, existing, options.dryRun, actions);
  let next: string;
  try { next = format === "toml" ? mergeTomlManagedBlock(existing, body, options.force) : mergeManagedBlock(existing, body, options.force); }
  catch (error) { if (options.force && existing) await backupFile(target, existing, options.dryRun, actions); throw error; }
  if (!options.dryRun && next !== existing) await writeAbsoluteAtomic(target, next);
  actions.push(`${options.dryRun ? "PLAN BLOCK" : next === existing ? "UNCHANGED BLOCK" : "BLOCK"} ${target}#${id}`);
}

async function planJsoncChange(target: string, keyPath: (string | number)[], value: unknown, options: Pick<InstallOptions, "dryRun" | "clearGlobalConfig">, actions: string[]): Promise<ConfigChange> {
  let existing = "{}\n";
  if (!(options.clearGlobalConfig && options.dryRun)) {
    try { existing = await readFile(target, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  const previous = getJsoncValue(existing, keyPath);
  const next = setJsoncValue(existing, keyPath, value);
  if (!options.dryRun && next !== existing) await writeAbsoluteAtomic(target, next);
  actions.push(`${options.dryRun ? "PLAN CONFIG" : "CONFIG"} ${target}:${keyPath.join(".")}`);
  return { path: target, keyPath, value, previousExists: previous.exists, previousValue: previous.value };
}

async function restoreJsoncChange(change: ConfigChange, dryRun: boolean, actions: string[]): Promise<void> {
  let existing: string;
  try { existing = await readFile(change.path, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return; throw error; }
  const current = getJsoncValue(existing, change.keyPath);
  if (JSON.stringify(current.value) !== JSON.stringify(change.value)) return;
  const next = setJsoncValue(existing, change.keyPath, change.previousExists ? change.previousValue : undefined);
  if (!dryRun) await writeAbsoluteAtomic(change.path, next);
  actions.push(`${dryRun ? "PLAN CONFIG RESTORE" : "CONFIG RESTORE"} ${change.path}:${change.keyPath.join(".")}`);
}

async function ensureGitignoreLine(repo: string, line: string, options: Pick<InstallOptions, "dryRun">, actions: string[]): Promise<boolean> {
  const target = path.join(repo, ".gitignore");
  let existing = "";
  try { existing = await readFile(target, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  if (existing.split(/\r?\n/).includes(line)) return false;
  const next = `${existing.trimEnd()}${existing.trim() ? "\n" : ""}${line}\n`;
  if (!options.dryRun) await writeAbsoluteAtomic(target, next);
  actions.push(`${options.dryRun ? "PLAN IGNORE" : "IGNORE"} ${line}`);
  return true;
}

function codexSecurityBody(security: SecurityProfile): string {
  const lines: string[] = [];
  if (security === "guarded") lines.push('approval_policy = "on-request"', 'sandbox_mode = "workspace-write"');
  if (security === "permissive") lines.push('approval_policy = "never"', 'sandbox_mode = "danger-full-access"');
  return lines.join("\n");
}

function primaryOpenCodeFile(paths: HostPaths, orchestrator: string): { target: string; content: string; sourceId: string } {
  const sourceId = "primary-profile:agentic-kit";
  const content = `---\ndescription: Main Agentic Coding Kit orchestrator\nmode: primary\n---\n\n<!-- ${GENERATED_MARKER}; source=core/orchestrator.md; sourceId=${sourceId} -->\n${orchestrator.trim()}\n`;
  return { target: path.join(paths.agents, "agentic-kit.md"), content, sourceId };
}

function invocationNote(host: Host): string {
  if (host === "codex") return "Use `$build`, `$design`, `$analyze`, `$review`, `$pr-ready`, `$threat-model`, and `$wiki`.";
  if (host === "claude") return "Use `/build`, `/design`, `/analyze`, `/review`, `/pr-ready`, `/threat-model`, and `/wiki`.";
  if (host === "opencode") return "Use native skills or installed thin commands; direct specialists use `@agent`.";
  return "Request a kit skill in natural language; use `/skills` for discovery and `/agent` for custom-agent selection.";
}

function installManifestPath(paths: HostPaths): string { return path.join(paths.administrationRoot, `install-${paths.host}-${paths.scope}.json`); }
async function readInstallManifest(target: string): Promise<InstallManifest | undefined> { try { return JSON.parse(await readFile(target, "utf8")) as InstallManifest; } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined; throw error; } }
async function writeAbsoluteAtomic(target: string, content: string): Promise<void> { await atomicWriteContained(path.dirname(target), path.basename(target), content, "managed target directory"); }
async function backupFile(target: string, content: string, dryRun: boolean, actions: string[]): Promise<void> { const backup = `${target}.agentic-kit-backup-${Date.now()}`; if (!dryRun) await writeAbsoluteAtomic(backup, content); actions.push(`${dryRun ? "PLAN BACKUP" : "BACKUP"} ${backup}`); }
function sha256(content: string): string { return createHash("sha256").update(content, "utf8").digest("hex"); }
function samePath(a: string, b: string): boolean { return path.resolve(a).toLowerCase() === path.resolve(b).toLowerCase(); }
function hasGeneratedHeader(content: string, sourceId: string): boolean { return content.includes(`${GENERATED_MARKER};`) && content.includes(`sourceId=${sourceId}`); }
function isLegacyKitOwned(content: string): boolean {
  return /@generated by Agentic Coding Kit/i.test(content)
    || /agentic[- ]coding[- ]kit/i.test(content)
    || /(?:^|[\\/])\.kit[\\/](?:workflows|context|session-state)/im.test(content)
    || /~[\\/]\.agents[\\/](?:instructions|tools|workflows)/i.test(content);
}

export function preserveLocalCodexModelOverride(target: string, existing: string, generated: string, previous?: ManagedFile): string {
  if (!target.endsWith(".toml")) return generated;
  const normalizedExisting = existing.replace(/\r\n/g, "\n");
  const match = normalizedExisting.match(/\nmodel = "([^"]+)"\nmodel_reasoning_effort = "([^"]+)"\n?$/);
  if (!match) return generated;
  const withoutOverride = normalizedExisting.slice(0, match.index! + 1);
  const trustedModelOnlyChange = withoutOverride === generated.replace(/\r\n/g, "\n")
    || Boolean(previous && previous.sourceId && (sha256(withoutOverride) === previous.sha256 || sha256(normalizedExisting) === previous.sha256));
  if (!trustedModelOnlyChange) return generated;
  return `${generated.replace(/\r\n/g, "\n").trimEnd()}\nmodel = "${match[1]}"\nmodel_reasoning_effort = "${match[2]}"\n`;
}

async function anotherInstallOwnsBlock(paths: HostPaths, currentManifest: string, blockPath: string): Promise<boolean> {
  let files: string[];
  try { files = await readdir(paths.administrationRoot); } catch { return false; }
  for (const file of files.filter((item) => item.startsWith("install-") && item.endsWith(".json"))) {
    const candidate = path.join(paths.administrationRoot, file);
    if (samePath(candidate, currentManifest)) continue;
    const manifest = await readInstallManifest(candidate);
    if (manifest?.managedBlocks.some((block) => samePath(block.path, blockPath))) return true;
  }
  return false;
}

function carryOriginalChange(change: ConfigChange, previous: InstallManifest | undefined): ConfigChange {
  const prior = previous?.configChanges.find((item) => samePath(item.path, change.path) && item.keyPath.join(".") === change.keyPath.join("."));
  return prior ? { ...change, previousExists: prior.previousExists, previousValue: prior.previousValue } : change;
}

async function removeManagedLine(managed: ManagedLine, dryRun: boolean, actions: string[]): Promise<void> {
  let content: string;
  try { content = await readFile(managed.path, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return; throw error; }
  const lines = content.split(/\r?\n/);
  const index = lines.indexOf(managed.line);
  if (index < 0) return;
  lines.splice(index, 1);
  if (!dryRun) await writeAbsoluteAtomic(managed.path, `${lines.join("\n").replace(/\n+$/, "")}\n`);
  actions.push(`${dryRun ? "PLAN LINE REMOVE" : "LINE REMOVE"} ${managed.path}:${managed.line}`);
}

function isAmbiguousManagedBlock(content: string, format: "markdown" | "toml"): boolean {
  const start = format === "toml" ? "# agentic-coding-kit:start" : "<!-- agentic-coding-kit:start -->";
  const end = format === "toml" ? "# agentic-coding-kit:end" : "<!-- agentic-coding-kit:end -->";
  return content.split(start).length - 1 !== content.split(end).length - 1 || content.split(start).length - 1 > 1;
}

async function resetGlobalConfig(paths: HostPaths, options: InstallOptions, actions: string[]): Promise<void> {
  const home = path.resolve(options.pathContext?.home ?? os.homedir());
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupRoot = path.join(home, ".agentic-kit-backup", stamp, paths.host);
  const targets = [
    { label: "instructions", target: paths.instruction },
    { label: "agents", target: paths.agents },
    { label: "skills", target: paths.skills },
    ...(paths.commands ? [{ label: "commands", target: paths.commands }] : []),
    ...(paths.config ? [{ label: "config", target: paths.config }] : []),
    { label: "administration", target: paths.administrationRoot },
    ...additionalGlobalResetTargets(paths),
  ];
  const seen = new Set<string>();
  for (const item of targets) {
    const resolved = path.resolve(item.target);
    const key = process.platform === "win32" ? resolved.toLowerCase() : resolved;
    if (seen.has(key)) continue;
    seen.add(key);
    try { await lstat(resolved); } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") continue;
      throw error;
    }
    const backup = path.join(backupRoot, item.label, path.basename(resolved));
    actions.push(`${options.dryRun ? "PLAN BACKUP+RESET" : "BACKUP+RESET"} ${resolved} -> ${backup}`);
    if (options.dryRun) continue;
    await mkdir(path.dirname(backup), { recursive: true });
    await cp(resolved, backup, { recursive: true, errorOnExist: true, force: false });
    await rm(resolved, { recursive: true, force: false });
  }
}

function additionalGlobalResetTargets(paths: HostPaths): Array<{ label: string; target: string }> {
  if (paths.host === "codex") {
    const codexHome = path.dirname(paths.agents);
    return [
      { label: "legacy-reference", target: path.join(codexHome, "agentic-kit.md") },
      { label: "legacy-skills", target: path.join(codexHome, "skills") },
      { label: "rules", target: path.join(codexHome, "rules") },
      { label: "prompts", target: path.join(codexHome, "prompts") },
    ];
  }
  if (paths.host === "claude") return [
    { label: "legacy-reference", target: path.join(paths.root, "agentic-kit.md") },
    { label: "commands", target: path.join(paths.root, "commands") },
    { label: "mcp", target: path.join(paths.root, ".mcp.json") },
    { label: "local-settings", target: path.join(paths.root, "settings.local.json") },
  ];
  if (paths.host === "opencode") return [
    { label: "legacy-reference", target: path.join(paths.root, "agentic-kit.md") },
  ];
  return [
    { label: "legacy-reference", target: path.join(paths.root, "agentic-kit.md") },
    { label: "instructions-directory", target: path.join(paths.root, "instructions") },
  ];
}
