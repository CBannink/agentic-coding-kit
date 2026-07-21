import { execFile as execFileCallback } from "node:child_process";
import { mkdir, mkdtemp, readFile, readdir, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";
import { doctorHost } from "../src/doctor.js";
import { installHost, uninstallHost, type InstallOptions } from "../src/install.js";
import { resolveHostPaths, type PathEnvironment } from "../src/host-paths.js";
import { migrateLegacy } from "../src/migrate.js";
import { parseFrontmatter, parseJsonc } from "../src/parsers.js";

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

  it("rejects linked legacy migration state without creating a backup", async () => {
    const fixture = await environment("kit-migrate-linked-");
    const outside = path.join(fixture.home, "outside-legacy");
    await mkdir(outside, { recursive: true });
    await writeFile(path.join(outside, "memory.md"), "outside\n", "utf8");
    await symlink(outside, path.join(fixture.repo, ".kit"), process.platform === "win32" ? "junction" : "dir");

    await expect(migrateLegacy(baseOptions("codex", "project", fixture))).rejects.toThrow(/linked legacy migration source/i);
    await expect(readdir(path.join(fixture.repo, ".agentic-kit-backup"))).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readFile(path.join(outside, "memory.md"), "utf8")).resolves.toBe("outside\n");
  });

  it("requires explicit consent for permissive mode and auto-selects the OpenCode primary", async () => {
    const fixture = await environment("kit-profiles-");
    await expect(installHost({ ...baseOptions("codex", "user", fixture), security: "permissive" })).rejects.toThrow(/requires.*--yes/i);
    const opencode = baseOptions("opencode", "user", fixture);
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    await mkdir(path.dirname(paths.config!), { recursive: true });
    await writeFile(paths.config!, '{\n  // retain\n  "provider": { "custom": true }\n}\n', "utf8");
    await installHost(opencode);
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).toMatchObject({ provider: { custom: true }, default_agent: "agentic-kit" });
    const primary = parseFrontmatter(await readFile(path.join(paths.agents, "agentic-kit.md"), "utf8"));
    expect(primary.data).toMatchObject({ mode: "primary" });
    expect(primary.data).not.toHaveProperty("permission");
    expect(primary.content.trim()).toBe("");
    await installHost({ ...opencode, setDefaultAgent: true });
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).toMatchObject({ provider: { custom: true }, default_agent: "agentic-kit" });
    await uninstallHost({ ...opencode, setDefaultAgent: true });
    expect(await readFile(paths.config!, "utf8")).toContain("// retain");
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).not.toHaveProperty("default_agent");
  }, 30_000);

  it("clears global harness configuration only with explicit consent", async () => {
    const fixture = await environment("kit-global-reset-");
    const options = baseOptions("codex", "user", fixture);
    const paths = await resolveHostPaths("codex", "user", undefined, fixture.context);
    await mkdir(paths.agents, { recursive: true });
    await mkdir(path.join(paths.skills, "old-skill"), { recursive: true });
    await mkdir(path.join(paths.skills, ".system"), { recursive: true });
    const codexCompatibilitySkills = path.join(path.dirname(paths.agents), "skills");
    await mkdir(path.join(codexCompatibilitySkills, ".system"), { recursive: true });
    await mkdir(path.join(codexCompatibilitySkills, "old-compatibility-skill"), { recursive: true });
    await mkdir(path.join(path.dirname(paths.agents), "rules", "old-rule"), { recursive: true });
    await mkdir(path.dirname(paths.instruction), { recursive: true });
    await writeFile(paths.instruction, "old global instructions\n", "utf8");
    await writeFile(path.join(paths.agents, "old-agent.toml"), "old agent\n", "utf8");
    await writeFile(path.join(paths.skills, "old-skill", "SKILL.md"), "old skill\n", "utf8");
    await writeFile(path.join(paths.skills, ".system", "host-owned.md"), "host owned\n", "utf8");
    await writeFile(path.join(codexCompatibilitySkills, ".system", "host-owned.md"), "host owned\n", "utf8");
    await writeFile(path.join(codexCompatibilitySkills, "old-compatibility-skill", "SKILL.md"), "old compatibility skill\n", "utf8");
    await writeFile(path.join(path.dirname(paths.agents), "rules", "old-rule", "rule.md"), "old rule\n", "utf8");
    await writeFile(paths.config!, "old config\n", "utf8");

    await expect(installHost({ ...options, clearGlobalConfig: true })).rejects.toThrow(/clear-global-config.*--yes/i);
    await expect(installHost({ ...options, scope: "project", repo: fixture.repo, clearGlobalConfig: true, yes: true })).rejects.toThrow(/scope user/i);
    const result = await installHost({ ...options, clearGlobalConfig: true, yes: true });

    expect(await readFile(paths.instruction, "utf8")).toContain("agentic-coding-kit:start");
    await expect(readFile(path.join(paths.agents, "old-agent.toml"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readFile(path.join(paths.skills, "old-skill", "SKILL.md"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readFile(path.join(paths.skills, ".system", "host-owned.md"), "utf8")).resolves.toBe("host owned\n");
    await expect(readFile(path.join(codexCompatibilitySkills, ".system", "host-owned.md"), "utf8")).resolves.toBe("host owned\n");
    await expect(readFile(path.join(codexCompatibilitySkills, "old-compatibility-skill", "SKILL.md"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readFile(path.join(path.dirname(paths.agents), "rules", "old-rule", "rule.md"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readFile(paths.config!, "utf8")).rejects.toMatchObject({ code: "ENOENT" });

    expect(result.actions.some((action) => action.startsWith("RESET "))).toBe(true);
    await expect(readdir(path.join(fixture.home, ".agentic-kit-backup"))).rejects.toMatchObject({ code: "ENOENT" });
  }, 30_000);

  it("clears a Codex host root outside the user home while preserving shared skills", async () => {
    const fixture = await environment("kit-global-reset-external-codex-");
    const codexHome = path.join(path.dirname(fixture.home), "external-codex");
    const context = { ...fixture.context, env: { ...fixture.context.env, CODEX_HOME: codexHome } };
    const options = { ...baseOptions("codex", "user", fixture), pathContext: context, clearGlobalConfig: true, yes: true };
    const paths = await resolveHostPaths("codex", "user", undefined, context);
    await mkdir(paths.agents, { recursive: true });
    await writeFile(path.join(paths.agents, "old-agent.toml"), "old\n", "utf8");

    await installHost(options);

    await expect(readFile(path.join(paths.agents, "old-agent.toml"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readFile(path.join(paths.agents, "reviewer.toml"), "utf8")).resolves.toContain("Independent Reviewer");
    await expect(readFile(path.join(paths.skills, "build", "SKILL.md"), "utf8")).resolves.toContain("# Build");
  }, 30_000);

  it("rejects unsafe explicit OpenCode reset configs before deleting any target", async () => {
    const fixture = await environment("kit-global-reset-unsafe-config-");
    const configRoot = fixture.context.env.OPENCODE_CONFIG_DIR!;
    const instruction = path.join(configRoot, "AGENTS.md");
    await mkdir(configRoot, { recursive: true });
    await writeFile(instruction, "keep instructions\n", "utf8");
    const outsideDirectory = path.join(fixture.home, "outside-config-directory");
    await mkdir(outsideDirectory, { recursive: true });

    for (const unsafeConfig of [outsideDirectory, fixture.home]) {
      const context = { ...fixture.context, env: { ...fixture.context.env, OPENCODE_CONFIG: unsafeConfig } };
      await expect(installHost({ ...baseOptions("opencode", "user", fixture), pathContext: context, clearGlobalConfig: true, yes: true }))
        .rejects.toThrow(/unsafe global reset config|regular file/i);
      await expect(readFile(instruction, "utf8")).resolves.toBe("keep instructions\n");
    }
  });

  it("rejects an explicit OpenCode config nested under agents before any reset deletion", async () => {
    const fixture = await environment("kit-global-reset-nested-config-");
    const configRoot = fixture.context.env.OPENCODE_CONFIG_DIR!;
    const instruction = path.join(configRoot, "AGENTS.md");
    const nestedConfig = path.join(configRoot, "agents", "nested.json");
    await mkdir(path.dirname(nestedConfig), { recursive: true });
    await writeFile(instruction, "keep instructions\n", "utf8");
    await writeFile(nestedConfig, "{}\n", "utf8");
    const context = { ...fixture.context, env: { ...fixture.context.env, OPENCODE_CONFIG: nestedConfig } };

    await expect(installHost({ ...baseOptions("opencode", "user", fixture), pathContext: context, clearGlobalConfig: true, yes: true }))
      .rejects.toThrow(/overlaps a managed reset directory/i);

    await expect(readFile(instruction, "utf8")).resolves.toBe("keep instructions\n");
    await expect(readFile(nestedConfig, "utf8")).resolves.toBe("{}\n");
  });

  it("rejects explicit OpenCode config symlinks and junctions before reset when links are available", async () => {
    const fixture = await environment("kit-global-reset-config-link-");
    const configRoot = fixture.context.env.OPENCODE_CONFIG_DIR!;
    const instruction = path.join(configRoot, "AGENTS.md");
    const fileTarget = path.join(fixture.home, "outside.json");
    const directoryTarget = path.join(fixture.home, "outside-directory");
    await mkdir(configRoot, { recursive: true });
    await mkdir(directoryTarget, { recursive: true });
    await writeFile(instruction, "keep instructions\n", "utf8");
    await writeFile(fileTarget, "{}\n", "utf8");
    const links = [
      { target: fileTarget, link: path.join(fixture.home, "outside-link.json"), kind: "file" as const },
      { target: directoryTarget, link: path.join(fixture.home, "outside-directory-link"), kind: process.platform === "win32" ? "junction" as const : "dir" as const },
    ];
    for (const item of links) {
      try {
        await symlink(item.target, item.link, item.kind);
      } catch (error) {
        if (["EPERM", "EACCES", "ENOTSUP"].includes((error as NodeJS.ErrnoException).code ?? "")) continue;
        throw error;
      }
      const context = { ...fixture.context, env: { ...fixture.context.env, OPENCODE_CONFIG: item.link } };
      await expect(installHost({ ...baseOptions("opencode", "user", fixture), pathContext: context, clearGlobalConfig: true, yes: true }))
        .rejects.toThrow(/regular file/i);
      await expect(readFile(instruction, "utf8")).resolves.toBe("keep instructions\n");
    }
    await expect(readFile(fileTarget, "utf8")).resolves.toBe("{}\n");
  });

  it("resets and recreates an explicit regular OpenCode config outside its config directory", async () => {
    const fixture = await environment("kit-global-reset-outside-config-");
    const outsideConfig = path.join(fixture.home, "outside.jsonc");
    await writeFile(outsideConfig, '{"old":true}\n', "utf8");
    const context = { ...fixture.context, env: { ...fixture.context.env, OPENCODE_CONFIG: outsideConfig } };

    await installHost({ ...baseOptions("opencode", "user", fixture), pathContext: context, clearGlobalConfig: true, yes: true });

    expect(parseJsonc(await readFile(outsideConfig, "utf8"))).toEqual({ default_agent: "agentic-kit" });
  }, 30_000);

  it.each([
    ["codex", "CODEX_HOME"],
    ["claude", "CLAUDE_CONFIG_DIR"],
    ["opencode", "OPENCODE_CONFIG_DIR"],
    ["copilot", "COPILOT_HOME"],
  ] as const)("rejects filesystem-root %s host configuration before any deletion", async (host, envName) => {
    const fixture = await environment(`kit-root-host-${host}-`);
    const sentinel = path.join(fixture.home, `${host}-keep.txt`);
    await writeFile(sentinel, "keep\n", "utf8");
    const filesystemRoot = path.parse(fixture.home).root;
    const context = {
      ...fixture.context,
      env: { ...fixture.context.env, [envName]: filesystemRoot, OPENCODE_CONFIG: undefined },
    };

    await expect(installHost({
      ...baseOptions(host, "user", fixture),
      pathContext: context,
      clearGlobalConfig: true,
      yes: true,
    })).rejects.toThrow(/filesystem-root host configuration/i);

    await expect(readFile(sentinel, "utf8")).resolves.toBe("keep\n");
  });

  it("ships thin launchers and four explicit release targets", async () => {
    const expected = ["install", "install-codex", "install-claude", "install-opencode", "install-copilot", "install-all"];
    for (const name of expected) {
      const shell = await readFile(path.join(sourceRoot, "scripts", `${name}.sh`), "utf8");
      const powershell = await readFile(path.join(sourceRoot, "scripts", `${name}.ps1`), "utf8");
      expect(shell.replace(/\r\n/g, "\n").startsWith("#!/usr/bin/env bash\nset -euo pipefail")).toBe(true);
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

    const fixture = await environment("kit-cli-confirm-");
    const env = { ...fixture.context.env, HOME: fixture.home, USERPROFILE: fixture.home, AGENTIC_KIT_ROOT: sourceRoot };
    await expect(execFile("node", [bundle, "install", "--host", "codex", "--scope", "user"], { encoding: "utf8", env })).rejects.toMatchObject({ stderr: expect.stringContaining("interactive confirmation or --yes") });
    const confirmed = await execFile("node", [bundle, "install", "--host", "codex", "--scope", "user", "--yes"], { encoding: "utf8", env });
    expect(confirmed.stderr).toContain("DESTRUCTIVE GLOBAL INSTALL");
    expect(confirmed.stdout).toContain("codex user");
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
