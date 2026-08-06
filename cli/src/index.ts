#!/usr/bin/env node
import { existsSync } from "node:fs";
import path from "node:path";
import { createInterface } from "node:readline/promises";
import { Command } from "commander";
import { loadManifest } from "./manifest.js";
import { checkGeneratedDrift, renderArtifacts, writeGenerated } from "./render.js";
import { validateCanonicalPrompts, validateGeneratedArtifacts } from "./validate.js";
import { auditWiki, initWiki, reinitWiki, type WikiSplit } from "./wiki.js";
import { GLOBAL_RESET_WARNING, installHost, uninstallHost, type CommandsMode, type InstallOptions, type MemoryProfile, type SecurityProfile } from "./install.js";
import type { Host, InstallProfile } from "./types.js";
import { doctorHost } from "./doctor.js";
import { migrateLegacy } from "./migrate.js";
import type { PrHistoryMode } from "./pr-history.js";

const moduleDir = typeof __dirname === "string"
  ? __dirname
  : path.resolve(process.cwd(), path.basename(process.cwd()).toLowerCase() === "cli" ? "src" : ".");
export const repoRoot = process.env.AGENTIC_KIT_ROOT
  ? path.resolve(process.env.AGENTIC_KIT_ROOT)
  : existsSync(path.join(process.cwd(), "core", "manifest.yaml"))
    ? path.resolve(process.cwd())
    : path.resolve(moduleDir, "..", "..");

const program = new Command()
  .name("kit")
  .description("Agentic Coding Kit v6.3 management CLI")
  .version("6.3.0")
  .addHelpText("after", "\nSecurity: do not run elevated against attacker-writable roots. Portable Node APIs cannot eliminate the final filesystem-operation race after ancestry validation.\n");

program.command("render")
  .description("Render native host adapters from canonical sources")
  .option("--profile <profile>", "core or full", "full")
  .option("--commands <mode>", "on or off", "on")
  .option("--check", "fail when checked-in generated artifacts drift")
  .action(async (options: { profile: InstallProfile; commands: string; check?: boolean }) => {
    assertChoice(options.profile, ["core", "full"]);
    assertChoice(options.commands, ["on", "off"]);
    const manifest = await loadManifest(repoRoot);
    const files = await renderArtifacts(repoRoot, manifest, {
      installProfile: options.profile,
      commands: options.commands === "on",
    });
    validateGeneratedArtifacts(files);
    if (options.check) {
      const drift = await checkGeneratedDrift(repoRoot, files);
      if (drift.length) throw new Error(`Generated adapter drift:\n${drift.join("\n")}`);
      console.log(`Generated adapters are current (${files.length} files).`);
      return;
    }
    await writeGenerated(repoRoot, files);
    console.log(`Rendered ${files.length} generated adapter files.`);
  });

configureManagementCommand(program.command("install").description("Install native Agentic Coding Kit files"), true)
  .action(async (options: ManagementCliOptions) => runInstall(options, true));
configureManagementCommand(program.command("update").description("Update an existing managed installation"), false)
  .action(async (options: ManagementCliOptions) => runInstall(options, false));
configureManagementCommand(program.command("uninstall").description("Remove only managed files and blocks"), false)
  .action(async (options: ManagementCliOptions) => runUninstall(options));
configureManagementCommand(program.command("doctor").description("Diagnose host discovery and managed installation state"), false)
  .action(async (options: ManagementCliOptions) => runDoctor(options));
configureManagementCommand(program.command("migrate").description("Back up known legacy state and install v6"), true)
  .action(async (options: ManagementCliOptions) => runMigrate(options));

program.command("validate")
  .description("Validate the manifest, canonical prompts, and generated adapter contract")
  .action(async () => {
    const manifest = await loadManifest(repoRoot);
    await validateCanonicalPrompts(repoRoot, manifest);
    const files = await renderArtifacts(repoRoot, manifest, { installProfile: "full", commands: true });
    validateGeneratedArtifacts(files);
    console.log(`Validated manifest, canonical prompts, and ${files.length} generated artifacts.`);
  });

const wiki = program.command("wiki").description("Initialize, reinitialize, or audit curated repository knowledge");

wiki.command("collect-pr-history")
  .description("Collect consented PR-review evidence into private Git metadata before wiki synthesis")
  .option("--repo <path>", "repository path", ".")
  .option("--mode <mode>", "auto or on", "auto")
  .action(async (options: { repo: string; mode: PrHistoryMode }) => {
    assertChoice(options.mode, ["auto", "on"]);
    const { collectPrHistory } = await import("./pr-history.js");
    const result = await collectPrHistory({ repo: options.repo, mode: options.mode, consented: options.mode === "on", interactive: Boolean(process.stdin.isTTY && process.stdout.isTTY) });
    console.log(`${result.status}${result.cachePath ? ` ${result.cachePath}` : result.reason ? `: ${result.reason}` : ""}`);
  });

wiki.command("init")
  .option("--repo <path>", "repository path", ".")
  .option("--wiki-split <mode>", "auto, root, or nested", "auto")
  .option("--dry-run", "report planned files without writing")
  .option("--synthesis <path>", "validated architect synthesis JSON inside the repository")
  .option("--pr-history <mode>", "optional PR history: auto, on, or off", "auto")
  .option("--yes", "accept non-interactive defaults")
  .action(async (options: { repo: string; wikiSplit: WikiSplit; dryRun?: boolean; synthesis?: string; prHistory: PrHistoryMode; yes?: boolean }) => {
    assertChoice(options.wikiSplit, ["auto", "root", "nested"]);
    assertChoice(options.prHistory, ["auto", "on", "off"]);
    printWikiResult(await initWiki({ repo: options.repo, wikiSplit: options.wikiSplit, dryRun: Boolean(options.dryRun), synthesis: options.synthesis, prHistory: options.prHistory, prHistoryConsented: options.prHistory === "on", interactive: Boolean(process.stdin.isTTY && process.stdout.isTTY) }));
  });

wiki.command("reinit")
  .option("--repo <path>", "repository path", ".")
  .option("--wiki-split <mode>", "auto, root, or nested", "auto")
  .option("--dry-run", "report planned files without writing")
  .option("--synthesis <path>", "validated architect synthesis JSON inside the repository")
  .option("--pr-history <mode>", "optional PR history: auto, on, or off", "auto")
  .option("--adopt-existing", "back up and replace an unmarked legacy wiki")
  .option("--yes", "accept non-interactive defaults")
  .action(async (options: { repo: string; wikiSplit: WikiSplit; dryRun?: boolean; synthesis?: string; prHistory: PrHistoryMode; adoptExisting?: boolean; yes?: boolean }) => {
    assertChoice(options.wikiSplit, ["auto", "root", "nested"]);
    assertChoice(options.prHistory, ["auto", "on", "off"]);
    let confirmed = Boolean(options.yes);
    if (options.adoptExisting && !options.dryRun && !confirmed) confirmed = await confirmWikiAdoption(options.repo);
    printWikiResult(await reinitWiki({
      repo: options.repo,
      wikiSplit: options.wikiSplit,
      dryRun: Boolean(options.dryRun),
      synthesis: options.synthesis,
      prHistory: options.prHistory,
      prHistoryConsented: options.prHistory === "on",
      interactive: Boolean(process.stdin.isTTY && process.stdout.isTTY),
      adoptExisting: Boolean(options.adoptExisting),
      confirmed,
    }));
  });

wiki.command("audit")
  .option("--repo <path>", "repository path", ".")
  .action(async (options: { repo: string }) => {
    printWikiResult(await auditWiki({ repo: options.repo }));
  });

program.parseAsync(process.argv).catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});

function assertChoice<T extends string>(value: string, choices: readonly T[]): asserts value is T {
  if (!(choices as readonly string[]).includes(value)) throw new Error(`Expected one of ${choices.join(", ")}; got ${value}`);
}

function printWikiResult(result: { status: string; files: string[]; findings?: Array<{ code: string; page: string; detail: string }> }): void {
  console.log(result.status);
  for (const file of result.files) console.log(file);
  for (const finding of result.findings ?? []) console.log(`${finding.code} ${finding.page}: ${finding.detail}`);
}

async function confirmWikiAdoption(repo: string): Promise<boolean> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) throw new Error("Legacy wiki adoption requires interactive confirmation or --yes");
  const prompt = createInterface({ input: process.stdin, output: process.stdout });
  try {
    const answer = (await prompt.question(`Back up and replace the unmarked wiki in ${path.resolve(repo)}? [y/N] `)).trim().toLowerCase();
    return answer === "y" || answer === "yes";
  } finally {
    prompt.close();
  }
}

interface ManagementCliOptions {
  host: string; scope: "user" | "project"; repo?: string; profile: InstallProfile;
  security: SecurityProfile; memory: MemoryProfile; commands: CommandsMode; setDefaultAgent?: boolean;
  dryRun?: boolean; force?: boolean; yes?: boolean; verbose?: boolean; wikiSplit?: WikiSplit; clearGlobalConfig?: boolean;
}

function configureManagementCommand(command: Command, hostRequired: boolean): Command {
  return command
    .option("--host <host>", "codex, claude, opencode, copilot, or all", hostRequired ? undefined : "all")
    .option("--scope <scope>", "user or project", "user")
    .option("--repo <path>", "project repository path")
    .option("--profile <profile>", "core or full", "core")
    .option("--security <profile>", "preserve, guarded, or permissive", "preserve")
    .option("--memory <profile>", "preserve or wiki-only", "preserve")
    .option("--wiki-split <mode>", "auto, root, or nested", "auto")
    .option("--set-default-agent", "override an existing OpenCode default with agentic-kit")
    .option("--clear-global-config", "back up and replace existing global harness instructions, agents, skills, commands, and primary config")
    .option("--commands <mode>", "auto, on, or off", "auto")
    .option("--dry-run", "show exact planned actions")
    .option("--force", "back up and replace conflicting managed targets")
    .option("--yes", "confirm non-interactive or permissive actions")
    .option("--verbose", "print detailed action output");
}

async function runInstall(options: ManagementCliOptions, replaceGlobalByDefault: boolean): Promise<void> {
  validateManagementOptions(options);
  const hosts = selectedHosts(options.host);
  const clearGlobalConfig = options.scope === "user" && (replaceGlobalByDefault || Boolean(options.clearGlobalConfig));
  let confirmed = Boolean(options.yes);
  if (clearGlobalConfig && !options.dryRun) {
    console.warn(GLOBAL_RESET_WARNING);
    if (!confirmed) confirmed = await confirmDestructiveInstall();
    if (!confirmed) {
      console.log("Installation cancelled; no files were changed.");
      return;
    }
  }
  if (hosts.length > 1 && !options.dryRun) {
    for (const host of hosts) {
      await installHost({ repoRoot, host, scope: options.scope, repo: options.repo, profile: options.profile, security: options.security, memory: options.memory, commands: options.commands, setDefaultAgent: Boolean(options.setDefaultAgent), dryRun: true, force: Boolean(options.force), yes: confirmed, verbose: Boolean(options.verbose), clearGlobalConfig });
    }
    console.log(`Preflight passed for ${hosts.join(", ")}.`);
  }
  for (const host of hosts) {
    const installOptions: InstallOptions = { repoRoot, host, scope: options.scope, repo: options.repo, profile: options.profile, security: options.security, memory: options.memory, commands: options.commands, setDefaultAgent: Boolean(options.setDefaultAgent), dryRun: Boolean(options.dryRun), force: Boolean(options.force), yes: confirmed, verbose: Boolean(options.verbose), clearGlobalConfig };
    if (options.security === "permissive") console.warn("PERMISSIVE AGENT PROFILE\n\nThis profile allows commands and file changes with little or no approval. The Agentic Coding Kit does not make arbitrary commands safe.");
    const result = await installHost(installOptions);
    console.log(`${result.host} ${result.scope}`);
    for (const action of result.actions) console.log(action);
    for (const warning of result.warnings) console.warn(`WARNING ${warning}`);
  }
}

async function confirmDestructiveInstall(): Promise<boolean> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) throw new Error("Destructive user installation requires interactive confirmation or --yes");
  const prompt = createInterface({ input: process.stdin, output: process.stdout });
  try {
    const answer = (await prompt.question("Continue and replace the selected global configuration? [y/N] ")).trim().toLowerCase();
    return answer === "y" || answer === "yes";
  } finally {
    prompt.close();
  }
}

async function runUninstall(options: ManagementCliOptions): Promise<void> {
  validateManagementOptions(options);
  for (const host of selectedHosts(options.host)) {
    const result = await uninstallHost({ repoRoot, host, scope: options.scope, repo: options.repo, dryRun: Boolean(options.dryRun), force: Boolean(options.force) });
    console.log(`${result.host} ${result.scope}`);
    for (const action of result.actions) console.log(action);
  }
}

async function runDoctor(options: ManagementCliOptions): Promise<void> {
  validateManagementOptions(options);
  let broken = false;
  for (const host of selectedHosts(options.host)) {
    const report = await doctorHost(host, options.scope, options.repo, undefined, repoRoot);
    console.log(`${host} ${report.platform}/${report.architecture}${report.version ? ` ${report.version}` : ""}`);
    for (const [name, resolved] of Object.entries(report.resolved)) if (resolved) console.log(`${name}: ${resolved}`);
    for (const warning of report.warnings) console.warn(`WARNING ${warning}`);
    for (const error of report.errors) { console.error(`ERROR ${error}`); broken = true; }
  }
  if (broken) process.exitCode = 1;
}

async function runMigrate(options: ManagementCliOptions): Promise<void> {
  validateManagementOptions(options);
  for (const host of selectedHosts(options.host)) {
    const installOptions: InstallOptions = { repoRoot, host, scope: options.scope, repo: options.repo, profile: options.profile, security: options.security, memory: options.memory, commands: options.commands, setDefaultAgent: Boolean(options.setDefaultAgent), dryRun: Boolean(options.dryRun), force: Boolean(options.force), yes: Boolean(options.yes), verbose: Boolean(options.verbose), clearGlobalConfig: Boolean(options.clearGlobalConfig) };
    const result = await migrateLegacy(installOptions);
    console.log(`Legacy candidates: ${result.candidates.join(", ") || "none"}`);
    console.log(`Backup: ${result.backupRoot}`);
    for (const action of result.install.actions) console.log(action);
  }
}

function validateManagementOptions(options: ManagementCliOptions): void {
  if (!options.host) throw new Error("--host is required");
  assertChoice(options.host, ["codex", "claude", "opencode", "copilot", "all"]);
  assertChoice(options.scope, ["user", "project"]);
  assertChoice(options.profile, ["core", "full"]);
  assertChoice(options.security, ["preserve", "guarded", "permissive"]);
  assertChoice(options.memory, ["preserve", "wiki-only"]);
  assertChoice(options.commands, ["auto", "on", "off"]);
}

function selectedHosts(value: string): Host[] {
  return value === "all" ? ["codex", "claude", "opencode", "copilot"] : [value as Host];
}
