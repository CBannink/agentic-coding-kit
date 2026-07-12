import { execFile as execFileCallback } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";
import { doctorHost } from "../src/doctor.js";
import { installHost, uninstallHost, type InstallOptions } from "../src/install.js";
import { resolveHostPaths, type PathEnvironment } from "../src/host-paths.js";
import { migrateLegacy } from "../src/migrate.js";
import { parseJsonc } from "../src/parsers.js";

const execFile = promisify(execFileCallback);
const sourceRoot = path.resolve(import.meta.dirname, "..", "..");

describe("management CLI infrastructure", () => {
  it("diagnoses managed hash conflicts and duplicate discovered skills", async () => {
    const fixture = await environment("kit-doctor-");
    const options = baseOptions("opencode", "project", fixture);
    await installHost(options);
    const paths = await resolveHostPaths("opencode", "project", fixture.repo, fixture.context);
    await mkdir(path.join(fixture.repo, ".agents", "skills", "build"), { recursive: true });
    await writeFile(path.join(fixture.repo, ".agents", "skills", "build", "SKILL.md"), "duplicate\n", "utf8");
    await writeFile(path.join(paths.agents, "reviewer.md"), "local edit\n", "utf8");
    const report = await doctorHost("opencode", "project", fixture.repo, fixture.context, sourceRoot);
    expect(report.errors).toEqual(expect.arrayContaining([expect.stringMatching(/Managed hash conflict/)]));
    expect(report.warnings).toEqual(expect.arrayContaining([expect.stringMatching(/Duplicate skill build/)]));
    expect(report.resolved.skills).toBe(paths.skills);
  }, 30_000);

  it("validates Codex TOML managed blocks independently from Markdown blocks", async () => {
    const fixture = await environment("kit-doctor-toml-");
    await installHost(baseOptions("codex", "user", fixture));
    const report = await doctorHost("codex", "user", undefined, fixture.context, sourceRoot);
    expect(report.errors).not.toEqual(expect.arrayContaining([expect.stringMatching(/Managed block broken/)]));
    expect(report.errors).toEqual([]);
  }, 30_000);

  it("reports global compatibility-path skill collisions for OpenCode", async () => {
    const fixture = await environment("kit-doctor-global-skills-");
    await installHost(baseOptions("codex", "user", fixture));
    await installHost(baseOptions("opencode", "user", fixture));
    const report = await doctorHost("opencode", "user", undefined, fixture.context, sourceRoot);
    expect(report.warnings).toEqual(expect.arrayContaining([expect.stringMatching(/Duplicate skill build/)]));
  }, 30_000);

  it("backs up legacy project state without deleting it and installs v6", async () => {
    const fixture = await environment("kit-migrate-");
    await mkdir(path.join(fixture.repo, ".kit", "context"), { recursive: true });
    await writeFile(path.join(fixture.repo, ".kit", "context", "memory.md"), "legacy fact\n", "utf8");
    const result = await migrateLegacy(baseOptions("codex", "project", fixture));
    expect(result.candidates).toContain(".kit");
    await expect(readFile(path.join(fixture.repo, ".kit", "context", "memory.md"), "utf8")).resolves.toBe("legacy fact\n");
    await expect(readFile(path.join(result.backupRoot, ".kit", "context", "memory.md"), "utf8")).resolves.toBe("legacy fact\n");
    expect(await readFile(path.join(fixture.repo, ".gitignore"), "utf8")).toContain(".agentic-kit-backup/");
    expect(await readFile(path.join(fixture.repo, "AGENTS.md"), "utf8")).toContain("agentic-coding-kit:start");
  }, 30_000);

  it("requires explicit consent for permissive mode and keeps default-agent opt-in", async () => {
    const fixture = await environment("kit-profiles-");
    await expect(installHost({ ...baseOptions("codex", "user", fixture), security: "permissive" })).rejects.toThrow(/requires.*--yes/i);
    const opencode = baseOptions("opencode", "user", fixture);
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    await mkdir(path.dirname(paths.config!), { recursive: true });
    await writeFile(paths.config!, '{\n  // retain\n  "provider": { "custom": true }\n}\n', "utf8");
    await installHost(opencode);
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).not.toHaveProperty("default_agent");
    await installHost({ ...opencode, setDefaultAgent: true });
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).toMatchObject({ provider: { custom: true }, default_agent: "agentic-kit" });
    await uninstallHost({ ...opencode, setDefaultAgent: true });
    expect(await readFile(paths.config!, "utf8")).toContain("// retain");
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).not.toHaveProperty("default_agent");
  }, 30_000);

  it("backs up and clears global harness configuration only with explicit consent", async () => {
    const fixture = await environment("kit-global-reset-");
    const options = baseOptions("codex", "user", fixture);
    const paths = await resolveHostPaths("codex", "user", undefined, fixture.context);
    await mkdir(paths.agents, { recursive: true });
    await mkdir(path.join(paths.skills, "old-skill"), { recursive: true });
    await mkdir(path.join(path.dirname(paths.agents), "rules", "old-rule"), { recursive: true });
    await mkdir(path.dirname(paths.instruction), { recursive: true });
    await writeFile(paths.instruction, "old global instructions\n", "utf8");
    await writeFile(path.join(paths.agents, "old-agent.toml"), "old agent\n", "utf8");
    await writeFile(path.join(paths.skills, "old-skill", "SKILL.md"), "old skill\n", "utf8");
    await writeFile(path.join(path.dirname(paths.agents), "rules", "old-rule", "rule.md"), "old rule\n", "utf8");
    await writeFile(paths.config!, "old config\n", "utf8");

    await expect(installHost({ ...options, clearGlobalConfig: true })).rejects.toThrow(/clear-global-config.*--yes/i);
    await expect(installHost({ ...options, scope: "project", repo: fixture.repo, clearGlobalConfig: true, yes: true })).rejects.toThrow(/scope user/i);
    await installHost({ ...options, clearGlobalConfig: true, yes: true });

    expect(await readFile(paths.instruction, "utf8")).toContain("agentic-coding-kit:start");
    await expect(readFile(path.join(paths.agents, "old-agent.toml"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readFile(path.join(paths.skills, "old-skill", "SKILL.md"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readFile(path.join(path.dirname(paths.agents), "rules", "old-rule", "rule.md"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readFile(paths.config!, "utf8")).rejects.toMatchObject({ code: "ENOENT" });

    const [stamp] = await readdir(path.join(fixture.home, ".agentic-kit-backup"));
    const backup = path.join(fixture.home, ".agentic-kit-backup", stamp, "codex");
    expect(await readFile(path.join(backup, "instructions", "AGENTS.md"), "utf8")).toBe("old global instructions\n");
    expect(await readFile(path.join(backup, "agents", "agents", "old-agent.toml"), "utf8")).toBe("old agent\n");
    expect(await readFile(path.join(backup, "skills", "skills", "old-skill", "SKILL.md"), "utf8")).toBe("old skill\n");
    expect(await readFile(path.join(backup, "rules", "rules", "old-rule", "rule.md"), "utf8")).toBe("old rule\n");
    expect(await readFile(path.join(backup, "config", "config.toml"), "utf8")).toBe("old config\n");
  }, 30_000);

  it("ships thin launchers and four explicit release targets", async () => {
    const expected = ["install", "install-codex", "install-claude", "install-opencode", "install-copilot", "install-all"];
    for (const name of expected) {
      const shell = await readFile(path.join(sourceRoot, "scripts", `${name}.sh`), "utf8");
      const powershell = await readFile(path.join(sourceRoot, "scripts", `${name}.ps1`), "utf8");
      expect(shell.startsWith("#!/usr/bin/env bash\nset -euo pipefail")).toBe(true);
      expect(shell).not.toMatch(/powershell|pwsh/i);
      expect(shell).toContain("cli/dist/kit.cjs");
      expect(powershell).toContain("@args");
      expect(powershell).toContain("$LASTEXITCODE");
    }
    const targets = JSON.parse(await readFile(path.join(sourceRoot, "cli", "packaging.targets.json"), "utf8")) as { targets: Array<{ platform: string; arch: string }> };
    expect(targets.targets).toEqual([
      { platform: "win32", arch: "x64", artifact: "kit-windows-x64" },
      { platform: "win32", arch: "arm64", artifact: "kit-windows-arm64" },
      { platform: "darwin", arch: "x64", artifact: "kit-macos-x64" },
      { platform: "darwin", arch: "arm64", artifact: "kit-macos-arm64" }
    ]);
    const bundle = path.join(sourceRoot, "cli", "dist", "kit.cjs");
    const topHelp = (await execFile("node", [bundle, "--help"], { encoding: "utf8" })).stdout;
    expect(topHelp).toMatch(/install|update|uninstall|doctor|validate|render|migrate|wiki/);
    const installHelp = (await execFile("node", [bundle, "install", "--help"], { encoding: "utf8" })).stdout;
    for (const flag of ["--scope", "--repo", "--profile", "--security", "--memory", "--wiki-split", "--set-default-agent", "--clear-global-config", "--commands", "--dry-run", "--force", "--yes", "--verbose"]) expect(installHelp).toContain(flag);
  });
});

function baseOptions(host: InstallOptions["host"], scope: InstallOptions["scope"], fixture: Awaited<ReturnType<typeof environment>>): InstallOptions {
  return { repoRoot: sourceRoot, host, scope, repo: scope === "project" ? fixture.repo : undefined, profile: "core", security: "preserve", memory: "preserve", commands: "auto", setDefaultAgent: false, dryRun: false, force: false, yes: false, verbose: false, pathContext: fixture.context };
}

async function environment(prefix: string): Promise<{ home: string; repo: string; context: PathEnvironment }> {
  const root = await mkdtemp(path.join(tmpdir(), prefix));
  const home = path.join(root, "home space Ω");
  const repo = path.join(root, "repo space Ω");
  await mkdir(home, { recursive: true });
  await mkdir(repo, { recursive: true });
  await execFile("git", ["init", "--quiet"], { cwd: repo });
  return { home, repo, context: { home, platform: process.platform, env: { ...process.env, CODEX_HOME: path.join(home, "codex"), CLAUDE_CONFIG_DIR: path.join(home, "claude"), OPENCODE_CONFIG_DIR: path.join(home, "opencode"), COPILOT_HOME: path.join(home, "copilot") } } };
}
