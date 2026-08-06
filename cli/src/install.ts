import { createHash } from "node:crypto";
import { lstat, mkdir, readFile, readdir, rm, unlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { atomicWriteContained, unlinkContained } from "./paths.js";
import { mergeManagedBlock, removeManagedBlock } from "./managed-block.js";
import { getJsoncValue, getTomlRootString, mergeTomlManagedBlock, removeTomlManagedBlock, setJsoncValue, setTomlRootString } from "./config-merge.js";
import { loadManifest } from "./manifest.js";
import { parseFrontmatter, serializeFrontmatter } from "./parsers.js";
import { renderArtifacts, GENERATED_MARKER } from "./render.js";
import { resolveHostPaths, type HostPaths, type InstallScope, type PathEnvironment } from "./host-paths.js";
import type { GeneratedFile, Host, InstallProfile } from "./types.js";

export type SecurityProfile = "preserve" | "guarded" | "permissive";
export type MemoryProfile = "preserve" | "wiki-only";
export type CommandsMode = "auto" | "on" | "off";

export const OPENCODE_PERMISSIVE_PERMISSIONS = {
  "*": "allow",
  bash: "allow",
  edit: "allow",
  external_directory: "allow",
  skill: "allow",
  task: "allow",
  webfetch: "allow",
} as const;

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
interface ConfigChange { path: string; keyPath: (string | number)[]; value: unknown; previousExists: boolean; previousValue: unknown; format?: "jsonc" | "toml" }
interface ManagedLine { path: string; line: string }
export interface InstallManifest {
  schemaVersion: 1; kitVersion: string; host: Host; scope: InstallScope; root: string;
  files: ManagedFile[]; managedBlocks: ManagedBlock[]; configChanges: ConfigChange[];
  managedLines: ManagedLine[];
  securityProfile: SecurityProfile; memoryProfile: MemoryProfile;
}
export interface InstallResult { host: Host; scope: InstallScope; actions: string[]; warnings: string[]; manifestPath: string }

export const GLOBAL_RESET_WARNING = `DESTRUCTIVE GLOBAL INSTALL

This installation replaces the selected harness's complete global
instructions, agents, skills, commands, and primary settings/config file.
Custom models, permissions, MCP configuration, and hooks in those locations
will be deleted. Back up or copy anything you want to keep before continuing.
Authentication credentials and opaque application state are not removed.`;

export async function installHost(options: InstallOptions): Promise<InstallResult> {
  if (options.security === "permissive" && !options.yes) throw new Error("PERMISSIVE AGENT PROFILE requires --security permissive --yes");
  if (options.clearGlobalConfig && options.scope !== "user") throw new Error("--clear-global-config is available only with --scope user");
  if (options.clearGlobalConfig && !options.yes) throw new Error("--clear-global-config requires --yes after reading the destructive-install warning");
  const paths = await resolveHostPaths(options.host, options.scope, options.repo, options.pathContext);
  if (options.host === "opencode" && paths.config) {
    await preflightOpenCodeConfig(paths.config, options.setDefaultAgent || Boolean(options.clearGlobalConfig), Boolean(options.clearGlobalConfig));
  }
  const actions: string[] = [];
  const backupRoot = managedBackupRoot(paths, options.pathContext);
  if (options.clearGlobalConfig) await resetGlobalConfig(paths, options, actions);
  const manifestPath = installManifestPath(paths);
  const previous = options.clearGlobalConfig ? undefined : await readInstallManifest(manifestPath);
  const canonical = await loadManifest(options.repoRoot);
  const commands = options.commands === "on" || (options.commands === "auto" && options.host === "opencode");
  const rendered = await renderArtifacts(options.repoRoot, canonical, { installProfile: options.profile, commands });
  const desired = mapRenderedFiles(rendered, paths);
  const orchestrator = await readFile(path.join(options.repoRoot, canonical.instruction_fragments.orchestrator), "utf8");
  if (options.host === "opencode") {
    const supplement = await readFile(path.join(options.repoRoot, canonical.instruction_fragments.opencode_primary), "utf8");
    desired.push(primaryOpenCodeFile(paths, orchestrator, supplement, canonical.instruction_fragments.orchestrator));
  }
  if (options.host === "codex") {
    const skillPaths = canonical.skills.map((skill) => path.join(paths.skills, skill.id, "SKILL.md"));
    for (const file of desired.filter((item) => samePath(path.dirname(item.target), paths.agents) && path.extname(item.target) === ".toml")) {
      file.content = isolateCodexSpecialist(file.content, skillPaths);
    }
  }
  if (options.host === "opencode" && options.security === "permissive") {
    for (const file of desired.filter((item) => samePath(path.dirname(item.target), paths.agents))) {
      file.content = permissiveOpenCodeAgent(file.content);
    }
  }
  if (options.host === "codex" && options.security === "permissive") {
    for (const file of desired.filter((item) => samePath(path.dirname(item.target), paths.agents) && path.extname(item.target) === ".toml")) {
      file.content = permissiveCodexAgent(file.content);
    }
  }
  const warnings: string[] = [];
  const files: ManagedFile[] = [];
  const blocks: ManagedBlock[] = [];
  const configChanges: ConfigChange[] = [];
  const managedLines: ManagedLine[] = [];

  for (const file of desired) {
    const installedContent = await planAndWriteFile(file.target, file.content, file.sourceId, previous?.files.find((item) => samePath(item.path, file.target)), options, backupRoot, actions);
    files.push({ path: file.target, sha256: sha256(installedContent), ownership: "managed", sourceId: file.sourceId });
  }
  const desiredTargets = new Set(files.map((file) => path.resolve(file.path).toLowerCase()));
  for (const stale of previous?.files ?? []) {
    if (desiredTargets.has(path.resolve(stale.path).toLowerCase())) continue;
    let current: string;
    try { current = await readFile(stale.path, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") continue; throw error; }
    if (sha256(current) !== stale.sha256) {
      if (!options.force) throw new Error(`Locally modified stale managed file conflict: ${stale.path}`);
      await backupFile(stale.path, current, options.dryRun, backupRoot, actions);
    }
    if (!options.dryRun) await unlinkContained(path.dirname(stale.path), path.basename(stale.path), "managed file directory");
    actions.push(`${options.dryRun ? "PLAN REMOVE" : "REMOVE"} ${stale.path}`);
  }

  const instructionBody = `${orchestrator.trim()}\n\n${invocationNote(options.host)}`;
  if (options.host === "claude" || options.host === "copilot") {
    await planAndMergeBlock(paths.instruction, instructionBody, "agentic-coding-kit", "markdown", options, backupRoot, actions);
    blocks.push({ path: paths.instruction, id: "agentic-coding-kit", bodyHash: sha256(instructionBody), format: "markdown" });
  }
  if (paths.hostInstruction) {
    const hostBody = "For GitHub Copilot CLI, request kit skills in natural language, inspect available skills with `/skills`, and select custom agents with `/agent` or supported `--agent` invocation. Shared orchestration rules are owned by the installed Copilot instruction file.";
    await planAndMergeBlock(paths.hostInstruction, hostBody, "agentic-coding-kit-copilot", "markdown", options, backupRoot, actions);
    blocks.push({ path: paths.hostInstruction, id: "agentic-coding-kit-copilot", bodyHash: sha256(hostBody), format: "markdown" });
  }

  if (options.host === "codex" && paths.config && options.security !== "preserve") {
    const body = codexSecurityBody(options.security);
    await planAndMergeBlock(paths.config, body, "agentic-coding-kit-profile", "toml", options, backupRoot, actions);
    blocks.push({ path: paths.config, id: "agentic-coding-kit-profile", bodyHash: sha256(body), format: "toml" });
  } else if (options.security !== "preserve" && !(options.host === "opencode" && options.security === "permissive")) {
    warnings.push(`${options.host} security profile preserved: no validated managed setting is emitted for this host`);
  }

  if (options.host === "codex" && paths.config) {
    const prior = previous?.configChanges.find((item) => samePath(item.path, paths.config!) && item.keyPath.join(".") === "developer_instructions");
    const current = await readTomlStringValue(paths.config, "developer_instructions", options);
    const original = prior
      ? { exists: prior.previousExists, value: prior.previousValue }
      : current;
    if (original.exists && typeof original.value !== "string") throw new Error("Codex developer_instructions must be a string");
    const primary = [original.exists ? String(original.value).trim() : "", instructionBody].filter(Boolean).join("\n\n");
    const change = await planTomlStringChange(paths.config, "developer_instructions", primary, options, actions);
    configChanges.push(carryOriginalChange(change, previous));
  }

  if (options.host === "claude" && options.scope === "project" && options.memory === "wiki-only" && paths.localSettings) {
    const change = carryOriginalChange(await planJsoncChange(paths.localSettings, ["autoMemoryEnabled"], false, options, actions), previous);
    configChanges.push(change);
    if (await ensureGitignoreLine(paths.root, ".claude/settings.local.json", options, actions)) managedLines.push({ path: path.join(paths.root, ".gitignore"), line: ".claude/settings.local.json" });
  } else if (options.memory === "wiki-only" && options.host !== "claude") warnings.push(`${options.host} has no managed auto-memory setting; preserved`);

  if (options.host === "opencode" && paths.config) {
    const currentDefault = await readJsoncValue(paths.config, ["default_agent"], options);
    const priorChange = previous?.configChanges.find((item) => samePath(item.path, paths.config!) && item.keyPath.join(".") === "default_agent");
    if (options.setDefaultAgent || !currentDefault.exists || currentDefault.value === "agentic-kit") {
      const change = await planJsoncChange(paths.config, ["default_agent"], "agentic-kit", options, actions);
      configChanges.push(priorChange
        ? carryOriginalChange(change, previous)
        : change);
    }
    if (options.security === "permissive") {
      const permissionChanges: Array<{ keyPath: (string | number)[]; value: typeof OPENCODE_PERMISSIVE_PERMISSIONS | Record<string, string> }> = [
        { keyPath: ["permission"], value: OPENCODE_PERMISSIVE_PERMISSIONS },
        ...desired
          .filter((file) => samePath(path.dirname(file.target), paths.agents) && path.extname(file.target) === ".md")
          .map((file) => ({
            keyPath: ["agent", path.basename(file.target, ".md"), "permission"],
            value: parseFrontmatter(file.content).data.mode === "subagent"
              ? { ...OPENCODE_PERMISSIVE_PERMISSIONS, skill: "deny", task: "deny" }
              : OPENCODE_PERMISSIVE_PERMISSIONS,
          })),
      ];
      for (const { keyPath, value } of permissionChanges) {
        const change = await planJsoncChange(paths.config, keyPath, value, options, actions);
        configChanges.push(carryOriginalChange(change, previous));
      }
    }
  }

  await retireStaleManagedBlocks(paths, manifestPath, previous, blocks, options, actions);

  const output: InstallManifest = { schemaVersion: 1, kitVersion: canonical.kit_version, host: options.host, scope: options.scope, root: paths.root, files, managedBlocks: blocks, configChanges, managedLines, securityProfile: options.security, memoryProfile: options.memory };
  if (!options.dryRun) await writeAbsoluteAtomic(manifestPath, `${JSON.stringify(output, null, 2)}\n`);
  actions.push(`${options.dryRun ? "PLAN" : "WRITE"} ${manifestPath}`);
  return { host: options.host, scope: options.scope, actions, warnings, manifestPath };
}

async function preflightOpenCodeConfig(target: string, setDefaultAgent: boolean, replaceConfig: boolean): Promise<void> {
  let state: Awaited<ReturnType<typeof lstat>> | undefined;
  try { state = await lstat(target); } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  if (state?.isSymbolicLink() || (state && !state.isFile())) {
    throw new Error(`OpenCode configuration must be missing or a regular file and not a symlink/junction: ${target}`);
  }
  const source = state && !replaceConfig ? await readFile(target, "utf8") : "{}\n";
  const current = getJsoncValue(source, ["default_agent"]);
  if (setDefaultAgent || !current.exists || current.value === "agentic-kit") {
    const planned = setJsoncValue(source, ["default_agent"], "agentic-kit");
    const resolved = getJsoncValue(planned, ["default_agent"]);
    if (!resolved.exists || resolved.value !== "agentic-kit") {
      throw new Error(`Cannot safely plan OpenCode default_agent configuration mutation: ${target}`);
    }
  }
}

export async function uninstallHost(options: Pick<InstallOptions, "host" | "scope" | "repo" | "dryRun" | "force" | "repoRoot" | "pathContext">): Promise<InstallResult> {
  const paths = await resolveHostPaths(options.host, options.scope, options.repo, options.pathContext);
  const manifestPath = installManifestPath(paths);
  const manifest = await readInstallManifest(manifestPath);
  if (!manifest) return { host: options.host, scope: options.scope, actions: ["NOT INSTALLED"], warnings: [], manifestPath };
  const actions: string[] = [];
  const backupRoot = managedBackupRoot(paths, options.pathContext);
  for (const file of manifest.files) {
    try {
      const current = await readFile(file.path, "utf8");
      if (sha256(current) !== file.sha256) {
        if (!options.force) throw new Error(`Locally modified managed file conflict: ${file.path}`);
        await backupFile(file.path, current, options.dryRun, backupRoot, actions);
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
  for (const change of manifest.configChanges) await restoreConfigChange(change, options.dryRun, actions);
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

async function planAndWriteFile(target: string, content: string, sourceId: string, previous: ManagedFile | undefined, options: Pick<InstallOptions, "force" | "dryRun" | "clearGlobalConfig">, backupRoot: string, actions: string[]): Promise<string> {
  let existing: string | undefined;
  if (!(options.clearGlobalConfig && options.dryRun)) {
    try { existing = await readFile(target, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  const effectiveContent = existing ? preserveLocalCodexModelOverride(target, existing, content, previous) : content;
  if (existing !== undefined && existing !== effectiveContent) {
    const trusted = previous && previous.sourceId === sourceId && sha256(existing) === previous.sha256;
    const legacyKitOwned = !previous && isLegacyKitOwned(existing);
    if (!trusted && !legacyKitOwned && !options.force) throw new Error(`Managed file conflict: ${target}`);
    if (!trusted && (legacyKitOwned || options.force)) await backupFile(target, existing, options.dryRun, backupRoot, actions);
  }
  if (!options.dryRun && existing !== effectiveContent) await writeAbsoluteAtomic(target, effectiveContent);
  actions.push(`${options.dryRun ? "PLAN WRITE" : existing === effectiveContent ? "UNCHANGED" : "WRITE"} ${target}`);
  return effectiveContent;
}

async function planAndMergeBlock(target: string, body: string, id: string, format: "markdown" | "toml", options: Pick<InstallOptions, "force" | "dryRun" | "clearGlobalConfig">, backupRoot: string, actions: string[]): Promise<void> {
  let existing = "";
  if (!(options.clearGlobalConfig && options.dryRun)) {
    try { existing = await readFile(target, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  if (options.force && existing && isAmbiguousManagedBlock(existing, format)) await backupFile(target, existing, options.dryRun, backupRoot, actions);
  let next: string;
  try { next = format === "toml" ? mergeTomlManagedBlock(existing, body, options.force) : mergeManagedBlock(existing, body, options.force); }
  catch (error) { if (options.force && existing) await backupFile(target, existing, options.dryRun, backupRoot, actions); throw error; }
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
  return { path: target, keyPath, value, previousExists: previous.exists, previousValue: previous.value, format: "jsonc" };
}

async function planTomlStringChange(target: string, key: string, value: string, options: Pick<InstallOptions, "dryRun" | "clearGlobalConfig">, actions: string[]): Promise<ConfigChange> {
  let existing = "";
  if (!(options.clearGlobalConfig && options.dryRun)) {
    try { existing = await readFile(target, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  const previous = getTomlRootString(existing, key);
  const next = setTomlRootString(existing, key, value);
  if (!options.dryRun && next !== existing) await writeAbsoluteAtomic(target, next);
  actions.push(`${options.dryRun ? "PLAN CONFIG" : "CONFIG"} ${target}:${key}`);
  return { path: target, keyPath: [key], value, previousExists: previous.exists, previousValue: previous.value, format: "toml" };
}

async function readJsoncValue(target: string, keyPath: (string | number)[], options: Pick<InstallOptions, "dryRun" | "clearGlobalConfig">): Promise<{ exists: boolean; value: unknown }> {
  if (options.clearGlobalConfig && options.dryRun) return { exists: false, value: undefined };
  try { return getJsoncValue(await readFile(target, "utf8"), keyPath); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return { exists: false, value: undefined }; throw error; }
}

async function readTomlStringValue(target: string, key: string, options: Pick<InstallOptions, "dryRun" | "clearGlobalConfig">): Promise<{ exists: boolean; value: unknown }> {
  if (options.clearGlobalConfig && options.dryRun) return { exists: false, value: undefined };
  try { return getTomlRootString(await readFile(target, "utf8"), key); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return { exists: false, value: undefined }; throw error; }
}

async function restoreConfigChange(change: ConfigChange, dryRun: boolean, actions: string[]): Promise<void> {
  let existing: string;
  try { existing = await readFile(change.path, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return; throw error; }
  if (change.format === "toml") {
    if (change.keyPath.length !== 1 || typeof change.keyPath[0] !== "string") throw new Error("Managed TOML changes support one root string key");
    const key = change.keyPath[0];
    const current = getTomlRootString(existing, key);
    if (current.value !== change.value) return;
    const next = setTomlRootString(existing, key, change.previousExists ? String(change.previousValue) : undefined);
    if (!dryRun) await writeAbsoluteAtomic(change.path, next);
    actions.push(`${dryRun ? "PLAN CONFIG RESTORE" : "CONFIG RESTORE"} ${change.path}:${key}`);
    return;
  }
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

function permissiveOpenCodeAgent(content: string): string {
  const parsed = parseFrontmatter(content);
  const specialist = parsed.data.mode === "subagent";
  return serializeFrontmatter(
    {
      ...parsed.data,
      permission: specialist
        ? { ...OPENCODE_PERMISSIVE_PERMISSIONS, skill: "deny", task: "deny" }
        : OPENCODE_PERMISSIVE_PERMISSIONS,
    },
    parsed.content,
  );
}

function isolateCodexSpecialist(content: string, skillPaths: string[]): string {
  const entries = skillPaths.map((skillPath) => [
    "[[skills.config]]",
    `path = ${JSON.stringify(skillPath)}`,
    "enabled = false",
  ].join("\n"));
  return `${content.replace(/\s+$/, "")}\n\n[agents]\nenabled = false\n\n${entries.join("\n\n")}\n`;
}

function permissiveCodexAgent(content: string): string {
  const sandboxLines = content.match(/^sandbox_mode = "[^"\r\n]+"\r?$/gm) ?? [];
  if (sandboxLines.length !== 1) throw new Error("Codex agent must contain exactly one sandbox_mode setting");
  return content.replace(/^sandbox_mode = "[^"\r\n]+"\r?$/m, 'sandbox_mode = "danger-full-access"');
}

function primaryOpenCodeFile(paths: HostPaths, orchestrator: string, supplement: string, sourcePath: string): { target: string; content: string; sourceId: string } {
  const sourceId = "primary-profile:agentic-kit";
  const prompt = [orchestrator.trim(), supplement.trim()].filter(Boolean).join("\n\n");
  const content = `---\ndescription: Principal engineering orchestrator for end-to-end delivery\nmode: primary\n# ${GENERATED_MARKER}; source=${sourcePath}; sourceId=${sourceId}\n---\n\n${prompt.trim()}\n`;
  return { target: path.join(paths.agents, "agentic-kit.md"), content, sourceId };
}

function invocationNote(host: Host): string {
  if (host === "codex") return [
    "Use `$build`, `$design`, `$architecture`, `$grill`, `$analyze`, `$review`, `$pr-ready`, `$threat-model`, `$wiki`, and `$experiment`.",
    "Codex delegation: invoke a named specialist with its `agent_type` and `fork_turns: \"none\"`; never retry a rejected named-agent dispatch as an untyped full-history fork.",
  ].join("\n");
  if (host === "claude") return "Use `/build`, `/design`, `/architecture`, `/grill`, `/analyze`, `/review`, `/pr-ready`, `/threat-model`, `/wiki`, and `/experiment`.";
  if (host === "opencode") return "Use native skills or installed thin commands; direct specialists use `@agent`.";
  return "Request a kit skill in natural language; use `/skills` for discovery and `/agent` for custom-agent selection.";
}

function installManifestPath(paths: HostPaths): string { return path.join(paths.administrationRoot, `install-${paths.host}-${paths.scope}.json`); }
async function readInstallManifest(target: string): Promise<InstallManifest | undefined> { try { return JSON.parse(await readFile(target, "utf8")) as InstallManifest; } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined; throw error; } }
async function writeAbsoluteAtomic(target: string, content: string): Promise<void> { await atomicWriteContained(path.dirname(target), path.basename(target), content, "managed target directory"); }
async function backupFile(target: string, content: string, dryRun: boolean, backupRoot: string, actions: string[]): Promise<void> {
  const name = `${sha256(path.resolve(target)).slice(0, 12)}-${path.basename(target)}`;
  const backup = path.join(backupRoot, name);
  if (!dryRun) await writeAbsoluteAtomic(backup, content);
  actions.push(`${dryRun ? "PLAN BACKUP" : "BACKUP"} ${backup}`);
}
function managedBackupRoot(paths: HostPaths, context?: PathEnvironment): string {
  const home = path.resolve(context?.home ?? os.homedir());
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  return path.join(home, ".agentic-kit-backup", stamp, paths.host, `${paths.scope}-managed-files`);
}
function sha256(content: string): string { return createHash("sha256").update(content, "utf8").digest("hex"); }
function samePath(a: string, b: string): boolean { return path.resolve(a).toLowerCase() === path.resolve(b).toLowerCase(); }
function isLegacyKitOwned(content: string): boolean {
  return /@generated by Agentic Coding Kit/i.test(content)
    || /agentic[- ]coding[- ]kit/i.test(content)
    || /(?:^|[\\/])\.kit[\\/](?:workflows|context|session-state)/im.test(content)
    || /~[\\/]\.agents[\\/](?:instructions|tools|workflows)/i.test(content);
}

export function preserveLocalCodexModelOverride(target: string, existing: string, generated: string, previous?: ManagedFile): string {
  if (!target.endsWith(".toml")) return generated;
  try {
    const model = getTomlRootString(existing, "model");
    const effort = getTomlRootString(existing, "model_reasoning_effort");
    if (!model.exists || !model.value || !effort.exists || !effort.value) return generated;

    const withoutModel = setTomlRootString(existing, "model", undefined);
    const withoutOverrides = setTomlRootString(withoutModel, "model_reasoning_effort", undefined);
    const normalizedBase = withoutOverrides.replace(/\r\n/g, "\n").trimEnd();
    const normalizedGenerated = generated.replace(/\r\n/g, "\n").trimEnd();
    const trustedModelOnlyChange = normalizedBase === normalizedGenerated
      || Boolean(previous && previous.sourceId && [withoutOverrides, `${normalizedBase}\n`, normalizedBase].some((candidate) => sha256(candidate) === previous.sha256));
    if (!trustedModelOnlyChange) return generated;

    return setTomlRootString(
      setTomlRootString(generated, "model", model.value),
      "model_reasoning_effort",
      effort.value,
    );
  } catch {
    return generated;
  }
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

async function retireStaleManagedBlocks(
  paths: HostPaths,
  currentManifest: string,
  previous: InstallManifest | undefined,
  current: ManagedBlock[],
  options: Pick<InstallOptions, "dryRun" | "force">,
  actions: string[],
): Promise<void> {
  const currentKeys = new Set(current.map((block) => `${path.resolve(block.path).toLowerCase()}#${block.id}`));
  const candidates = previous?.managedBlocks ?? (
    paths.host === "codex" || paths.host === "opencode"
      ? [{ path: paths.instruction, id: "agentic-coding-kit", bodyHash: "", format: "markdown" as const }]
      : []
  );
  for (const block of candidates) {
    if (currentKeys.has(`${path.resolve(block.path).toLowerCase()}#${block.id}`)) continue;
    if (await anotherInstallOwnsBlock(paths, currentManifest, block.path)) continue;
    let existing: string;
    try { existing = await readFile(block.path, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") continue; throw error; }
    if (!existing.includes("agentic-coding-kit:start")) continue;
    const next = block.format === "toml" ? removeTomlManagedBlock(existing, options.force) : removeManagedBlock(existing, options.force);
    if (!options.dryRun && next !== existing) await writeAbsoluteAtomic(block.path, next);
    actions.push(`${options.dryRun ? "PLAN BLOCK RETIRE" : "BLOCK RETIRE"} ${block.path}#${block.id}`);
  }
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
  const hostRoot = path.resolve(paths.hostRoot);
  const resetRoot = path.resolve(paths.root);
  if (samePath(hostRoot, path.parse(hostRoot).root)) throw new Error(`Refusing filesystem-root host configuration: ${hostRoot}`);
  if (samePath(resetRoot, path.parse(resetRoot).root)) throw new Error(`Refusing filesystem-root reset boundary: ${resetRoot}`);
  const targets = [
    { label: "instructions", target: paths.instruction },
    { label: "agents", target: paths.agents },
    { label: "skills", target: paths.skills },
    ...(paths.commands ? [{ label: "commands", target: paths.commands }] : []),
    ...(paths.config ? [{ label: "config", target: paths.config }] : []),
    { label: "administration", target: paths.administrationRoot },
    ...additionalGlobalResetTargets(paths),
  ];
  const directoryResetLabels = new Set(["agents", "skills", "commands", "administration", "legacy-skills", "rules", "prompts", "instructions-directory"]);
  const directoryResetTargets = targets.filter((item) => directoryResetLabels.has(item.label)).map((item) => item.target);
  const validated: Array<{ label: string; target: string; boundary: string; exists: boolean; isDirectory: boolean }> = [];
  for (const item of targets) {
    const resolved = path.resolve(item.target);
    if (samePath(resolved, path.parse(resolved).root)) throw new Error(`Refusing global reset target at filesystem root: ${resolved}`);
    const boundary = isSameOrAncestor(resetRoot, resolved)
      ? resetRoot
      : isSameOrAncestor(hostRoot, resolved)
        ? hostRoot
        : item.label === "config"
          ? path.dirname(resolved)
          : undefined;
    if (!boundary) throw new Error(`Unsafe global reset target is outside validated host roots ${resetRoot} and ${hostRoot}: ${resolved}`);
    let state: Awaited<ReturnType<typeof lstat>> | undefined;
    try { state = await lstat(resolved); } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    if (item.label === "config") {
      if (targets.some((other) => other.label !== "config" && samePath(resolved, other.target))
          || directoryResetTargets.some((root) => pathsOverlap(resolved, root))) {
        throw new Error(`Unsafe global reset config target overlaps a managed reset directory: ${resolved}`);
      }
      if (state?.isSymbolicLink() || (state && !state.isFile())) {
        throw new Error(`Unsafe global reset config target must be missing or a regular file: ${resolved}`);
      }
    }
    if (state) await assertSafeResetAncestry(boundary, resolved);
    if (paths.host === "codex" && path.basename(resolved).toLowerCase() === "skills" && state && !state.isDirectory()) {
      throw new Error(`Unsafe Codex skills reset target must be a directory: ${resolved}`);
    }
    validated.push({ label: item.label, target: resolved, boundary, exists: Boolean(state), isDirectory: Boolean(state?.isDirectory()) });
  }

  const seen = new Set<string>();
  for (const item of validated) {
    const resolved = item.target;
    const key = process.platform === "win32" ? resolved.toLowerCase() : resolved;
    if (seen.has(key)) continue;
    seen.add(key);
    if (!item.exists) continue;
    if (paths.host === "codex" && path.basename(resolved).toLowerCase() === "skills") {
      actions.push(`${options.dryRun ? "PLAN RESET" : "RESET"} ${resolved} (preserve .system)`);
      if (options.dryRun) continue;
      await assertSafeResetTarget(item.boundary, resolved, item);
      for (const entry of await readdir(resolved, { withFileTypes: true })) {
        if (entry.name === ".system") continue;
        const child = path.join(resolved, entry.name);
        await assertSafeResetAncestry(item.boundary, child);
        const childState = await lstat(child);
        if (childState.isSymbolicLink()) throw new Error(`Refusing symlink or junction reset target: ${child}`);
        await rm(child, { recursive: childState.isDirectory(), force: false });
      }
      continue;
    }
    actions.push(`${options.dryRun ? "PLAN RESET" : "RESET"} ${resolved}`);
    if (options.dryRun) continue;
    await assertSafeResetTarget(item.boundary, resolved, item);
    if (item.label === "config") await unlink(resolved);
    else await rm(resolved, { recursive: item.isDirectory, force: false });
  }
}

async function assertSafeResetTarget(root: string, target: string, expected: { label: string; isDirectory: boolean }): Promise<void> {
  await assertSafeResetAncestry(root, target);
  const state = await lstat(target);
  if (state.isSymbolicLink()) throw new Error(`Refusing symlink or junction reset target: ${target}`);
  if (expected.label === "config" && !state.isFile()) throw new Error(`Reset config target is no longer a regular file: ${target}`);
  if (expected.label !== "config" && state.isDirectory() !== expected.isDirectory) throw new Error(`Reset target type changed before deletion: ${target}`);
}

async function assertSafeResetAncestry(root: string, target: string): Promise<void> {
  const resolvedRoot = path.resolve(root);
  const resolvedTarget = path.resolve(target);
  if (!isSameOrAncestor(resolvedRoot, resolvedTarget)) throw new Error(`Reset target escapes validated root ${resolvedRoot}: ${resolvedTarget}`);
  let current = resolvedRoot;
  const rootState = await lstat(current);
  if (rootState.isSymbolicLink() || !rootState.isDirectory()) throw new Error(`Unsafe reset root ancestry: ${current}`);
  for (const segment of path.relative(resolvedRoot, resolvedTarget).split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);
    const state = await lstat(current);
    if (state.isSymbolicLink()) throw new Error(`Symlink or junction in reset ancestry: ${current}`);
  }
}

function isSameOrAncestor(candidate: string, target: string): boolean {
  if (samePath(candidate, target)) return true;
  const relative = path.relative(path.resolve(candidate), path.resolve(target));
  return relative.length > 0 && relative !== ".." && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

function pathsOverlap(left: string, right: string): boolean {
  return isSameOrAncestor(left, right) || isSameOrAncestor(right, left);
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
