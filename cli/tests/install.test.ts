import { execFile as execFileCallback } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, readdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";
import { installHost, OPENCODE_PERMISSIVE_PERMISSIONS, preserveLocalCodexModelOverride, uninstallHost, type InstallOptions } from "../src/install.js";
import { setTomlRootString } from "../src/config-merge.js";
import { resolveHostPaths, type PathEnvironment } from "../src/host-paths.js";
import { parseFrontmatter, parseJsonc, parseToml } from "../src/parsers.js";
import type { Host } from "../src/types.js";

const execFile = promisify(execFileCallback);
const sourceRoot = path.resolve(import.meta.dirname, "..", "..");
const hosts: Host[] = ["codex", "claude", "opencode", "copilot"];

describe("managed native installation", () => {
  it.each(hosts)("installs %s at isolated user and project native paths", async (host) => {
    const fixture = await fixtureEnvironment(`kit-install-${host}-`);
    for (const scope of ["user", "project"] as const) {
      const options = baseOptions(host, scope, fixture);
      const result = await installHost(options);
      expect(result.actions.some((action) => /WRITE|BLOCK/.test(action))).toBe(true);
      const paths = await resolveHostPaths(host, scope, fixture.repo, fixture.context);
      if (host === "codex" || host === "opencode") await expect(readFile(paths.instruction, "utf8")).rejects.toMatchObject({ code: "ENOENT" });
      else await expect(readFile(paths.instruction, "utf8")).resolves.toContain("agentic-coding-kit:start");
      const agentNames = await readdir(paths.agents);
      expect(agentNames.some((name) => /reviewer/.test(name))).toBe(true);
      const skill = await readFile(path.join(paths.skills, "build", "SKILL.md"), "utf8");
      expect(parseFrontmatter(skill).data.name).toBe("build");
      const reviewer = await readFile(path.join(paths.agents, host === "codex" ? "reviewer.toml" : host === "copilot" ? "reviewer.agent.md" : "reviewer.md"), "utf8");
      if (host === "codex") {
        const parsed = parseToml(reviewer) as any;
        expect(parsed).toMatchObject({ name: "reviewer", agents: { enabled: false } });
        expect(parsed.skills.config).toEqual(expect.arrayContaining([expect.objectContaining({ enabled: false })]));
        expect(parseToml(await readFile(paths.config!, "utf8"))).toHaveProperty("developer_instructions", expect.stringContaining("Agentic Coding Kit Engineering Primary"));
      } else {
        const parsed = parseFrontmatter(reviewer);
        expect(parsed.data.description).toEqual(expect.any(String));
        if (host === "opencode") expect(parsed.data).toMatchObject({ permission: { skill: "deny", task: "deny" } });
      }
      await installHost(options);
      if (host === "claude" || host === "copilot") expect((await readFile(paths.instruction, "utf8")).split("agentic-coding-kit:start").length - 1).toBe(1);
      if (host === "codex") expect(parseToml(await readFile(paths.config!, "utf8"))).toHaveProperty("developer_instructions", expect.stringContaining("Agentic Coding Kit Engineering Primary"));
    }
  }, 30_000);

  it("keeps Codex and OpenCode out of AGENTS while Copilot owns its instruction block", async () => {
    const fixture = await fixtureEnvironment("kit-shared-block-");
    for (const host of ["codex", "opencode"] as Host[]) await installHost(baseOptions(host, "project", fixture));
    await expect(readFile(path.join(fixture.repo, "AGENTS.md"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await installHost(baseOptions("copilot", "project", fixture));
    const agents = await readFile(path.join(fixture.repo, "AGENTS.md"), "utf8");
    expect(agents.split("agentic-coding-kit:start").length - 1).toBe(1);
    expect(await readFile(path.join(fixture.repo, ".github", "copilot-instructions.md"), "utf8")).toContain("installed Copilot instruction file");
  }, 30_000);

  it("preserves an explicit local Codex agent model override during an update", async () => {
    const fixture = await fixtureEnvironment("kit-codex-model-override-");
    const options = baseOptions("codex", "user", fixture);
    await installHost(options);
    const paths = await resolveHostPaths("codex", "user", undefined, fixture.context);
    const scout = path.join(paths.agents, "repo-scout.toml");
    const withModel = setTomlRootString(setTomlRootString(await readFile(scout, "utf8"), "model", "gpt-5.6-luna"), "model_reasoning_effort", "medium");
    await writeFile(scout, withModel, "utf8");
    await installHost(options);
    expect(await readFile(scout, "utf8")).toContain('model = "gpt-5.6-luna"');
  }, 30_000);

  it("isolates the Codex primary, preserves prior developer instructions, and retires the old ACK AGENTS block", async () => {
    const fixture = await fixtureEnvironment("kit-codex-primary-isolation-");
    const options = baseOptions("codex", "user", fixture);
    const paths = await resolveHostPaths("codex", "user", undefined, fixture.context);
    await mkdir(path.dirname(paths.config!), { recursive: true });
    await writeFile(paths.config!, 'developer_instructions = "Keep my preference."\n\n[mcp_servers.keep]\ncommand = "keep"\n', "utf8");
    await writeFile(paths.instruction, "user content\n<!-- agentic-coding-kit:start -->\nold orchestrator\n<!-- agentic-coding-kit:end -->\n", "utf8");

    await installHost(options);

    const config = parseToml(await readFile(paths.config!, "utf8"));
    expect(config).toHaveProperty("developer_instructions", expect.stringMatching(/^Keep my preference\.\n\n# Agentic Coding Kit Engineering Primary/));
    expect(config).toHaveProperty("mcp_servers.keep.command", "keep");
    expect(await readFile(paths.instruction, "utf8")).toBe("user content\n");
    const reviewer = parseToml(await readFile(path.join(paths.agents, "reviewer.toml"), "utf8")) as any;
    expect(reviewer.developer_instructions).toContain("Independent Reviewer");
    expect(reviewer.developer_instructions).not.toContain("Agentic Coding Kit Engineering Primary");
    expect(reviewer.agents).toEqual({ enabled: false });
    expect(reviewer.skills.config.every((entry: { enabled: boolean }) => entry.enabled === false)).toBe(true);

    await uninstallHost(options);
    expect(parseToml(await readFile(paths.config!, "utf8"))).toMatchObject({ developer_instructions: "Keep my preference.", mcp_servers: { keep: { command: "keep" } } });
    expect(await readFile(paths.instruction, "utf8")).toBe("user content\n");
  }, 30_000);

  it("applies the permissive Codex sandbox mode to every installed agent", async () => {
    const fixture = await fixtureEnvironment("kit-codex-permissive-");
    const options = { ...baseOptions("codex", "user", fixture), profile: "full" as const, security: "permissive" as const, yes: true };
    const paths = await resolveHostPaths("codex", "user", undefined, fixture.context);

    await installHost(options);

    const agents = (await readdir(paths.agents)).filter((name) => name.endsWith(".toml"));
    expect(agents).toHaveLength(10);
    for (const agent of agents) {
      expect(parseToml(await readFile(path.join(paths.agents, agent), "utf8"))).toMatchObject({ sandbox_mode: "danger-full-access" });
    }
  }, 30_000);

  it("preserves permissive Codex sandbox mode and model overrides during a repeat update", async () => {
    const fixture = await fixtureEnvironment("kit-codex-permissive-update-");
    const options = { ...baseOptions("codex", "user", fixture), profile: "full" as const, security: "permissive" as const, yes: true };
    const paths = await resolveHostPaths("codex", "user", undefined, fixture.context);
    await installHost(options);
    const scout = path.join(paths.agents, "repo-scout.toml");
    const withModel = setTomlRootString(setTomlRootString(await readFile(scout, "utf8"), "model", "gpt-5.6-luna"), "model_reasoning_effort", "medium");
    await writeFile(scout, withModel, "utf8");

    await installHost(options);

    for (const agent of (await readdir(paths.agents)).filter((name) => name.endsWith(".toml"))) {
      expect(parseToml(await readFile(path.join(paths.agents, agent), "utf8"))).toMatchObject({ sandbox_mode: "danger-full-access" });
    }
    expect(parseToml(await readFile(scout, "utf8"))).toMatchObject({ model: "gpt-5.6-luna", model_reasoning_effort: "medium" });
  }, 30_000);

  it("reapplies a model-only Codex override when the generated prompt changes", () => {
    const oldGenerated = '# @generated by Agentic Coding Kit v6; source=x; sourceId=agent:repo-scout\nname = "repo-scout"\ndeveloper_instructions = "old"\n';
    const existing = `${oldGenerated}model = "gpt-5.6-luna"\nmodel_reasoning_effort = "medium"\n`;
    const newGenerated = oldGenerated.replace('"old"', '"new"');
    const previous = { path: "repo-scout.toml", sha256: createHash("sha256").update(oldGenerated).digest("hex"), ownership: "managed" as const, sourceId: "agent:repo-scout" };
    const updated = preserveLocalCodexModelOverride("repo-scout.toml", existing, newGenerated, previous);
    expect(updated).toContain('developer_instructions = "new"');
    expect(updated).toContain('model = "gpt-5.6-luna"');
  });

  it("supports core/full, command modes, conflicts, force backups, and owned uninstall", async () => {
    const fixture = await fixtureEnvironment("kit-managed-lifecycle-");
    const options = baseOptions("opencode", "user", fixture);
    await installHost({ ...options, profile: "full", commands: "on" });
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    await expect(readFile(path.join(paths.agents, "browser-qa.md"), "utf8")).resolves.toContain("Browser QA");
    await expect(readFile(path.join(paths.commands!, "build.md"), "utf8")).resolves.toContain("$ARGUMENTS");
    await installHost({ ...options, profile: "core", commands: "off" });
    await expect(readFile(path.join(paths.agents, "browser-qa.md"), "utf8")).rejects.toThrow();
    await expect(readFile(path.join(paths.agents, "security-reviewer.md"), "utf8")).resolves.toContain("Security Reviewer");
    await expect(readFile(path.join(paths.skills, "threat-model", "SKILL.md"), "utf8")).resolves.toContain("# Threat Model");
    await expect(readFile(path.join(paths.commands!, "build.md"), "utf8")).rejects.toThrow();

    const reviewer = path.join(paths.agents, "reviewer.md");
    await writeFile(reviewer, `${await readFile(reviewer, "utf8")}\nlocal edit\n`, "utf8");
    await expect(installHost(options)).rejects.toThrow(/conflict/i);
    const forced = await installHost({ ...options, force: true });
    const forcedBackup = forced.actions.find((action) => action.startsWith("BACKUP "))!.slice("BACKUP ".length);
    expect(forcedBackup).toContain(`${path.sep}.agentic-kit-backup${path.sep}`);
    await expect(readFile(forcedBackup, "utf8")).resolves.toContain("local edit");
    expect((await readdir(paths.agents)).some((name) => name.includes("backup"))).toBe(false);
    const custom = path.join(paths.agents, "custom.md");
    await writeFile(custom, "custom\n", "utf8");
    await uninstallHost(options);
    await expect(readFile(reviewer, "utf8")).rejects.toThrow();
    await expect(readFile(custom, "utf8")).resolves.toBe("custom\n");
  }, 30_000);

  it("backs up and replaces recognizable legacy kit skills without force", async () => {
    const fixture = await fixtureEnvironment("kit-legacy-skill-");
    const options = baseOptions("codex", "user", fixture);
    const paths = await resolveHostPaths("codex", "user", undefined, fixture.context);
    const analyze = path.join(paths.skills, "analyze", "SKILL.md");
    await mkdir(path.dirname(analyze), { recursive: true });
    await writeFile(analyze, "---\nname: analyze\n---\n\nLoad .kit/workflows/analyze.md and ~/.agents/instructions.md.\n", "utf8");

    const result = await installHost(options);

    const backup = result.actions.find((action) => action.startsWith("BACKUP "))!.slice("BACKUP ".length);
    expect(backup).toContain(`${path.sep}.agentic-kit-backup${path.sep}`);
    await expect(readFile(backup, "utf8")).resolves.toContain(".kit/workflows/analyze.md");
    expect(await readFile(analyze, "utf8")).toContain("# Analyze");
    expect((await readdir(path.dirname(analyze))).some((name) => name.includes("backup"))).toBe(false);
  }, 30_000);

  it("still protects an unowned same-name skill", async () => {
    const fixture = await fixtureEnvironment("kit-custom-skill-");
    const options = baseOptions("codex", "user", fixture);
    const paths = await resolveHostPaths("codex", "user", undefined, fixture.context);
    const analyze = path.join(paths.skills, "analyze", "SKILL.md");
    await mkdir(path.dirname(analyze), { recursive: true });
    await writeFile(analyze, "---\nname: analyze\n---\n\nMy unrelated private analysis process.\n", "utf8");

    await expect(installHost(options)).rejects.toThrow(/Managed file conflict/);
    expect(await readFile(analyze, "utf8")).toContain("unrelated private analysis");
  }, 30_000);

  it("preserves JSONC/TOML settings and restores managed keys on uninstall", async () => {
    const fixture = await fixtureEnvironment("kit-config-preserve-");
    const claudePaths = await resolveHostPaths("claude", "project", fixture.repo, fixture.context);
    await mkdir(path.dirname(claudePaths.localSettings!), { recursive: true });
    await writeFile(claudePaths.localSettings!, '{\n  // keep\n  "theme": "dark",\n  "autoMemoryEnabled": true\n}\n', "utf8");
    const claude = { ...baseOptions("claude", "project", fixture), memory: "wiki-only" as const };
    await installHost(claude);
    expect(parseJsonc(await readFile(claudePaths.localSettings!, "utf8"))).toMatchObject({ theme: "dark", autoMemoryEnabled: false });
    await uninstallHost(claude);
    expect(parseJsonc(await readFile(claudePaths.localSettings!, "utf8"))).toMatchObject({ theme: "dark", autoMemoryEnabled: true });
    expect(await readFile(claudePaths.localSettings!, "utf8")).toContain("// keep");

    const codexPaths = await resolveHostPaths("codex", "user", undefined, fixture.context);
    await mkdir(path.dirname(codexPaths.config!), { recursive: true });
    await writeFile(codexPaths.config!, '# agentic-coding-kit:start\n[profiles.agentic-kit]\nmodel = "old"\n\n[projects.\'c:\\repo\']\ntrust_level = "trusted"\n# agentic-coding-kit:end\n\n[mcp_servers.keep]\ncommand = "keep"\n', "utf8");
    const codex = { ...baseOptions("codex", "user", fixture), security: "guarded" as const };
    await installHost(codex);
    const installedCodex = parseToml(await readFile(codexPaths.config!, "utf8"));
    expect(installedCodex).toHaveProperty("mcp_servers.keep.command", "keep");
    expect((installedCodex.projects as Record<string, unknown>)["c:\\repo"]).toMatchObject({ trust_level: "trusted" });
    expect(installedCodex).toMatchObject({ approval_policy: "on-request", sandbox_mode: "workspace-write" });
    expect(installedCodex).not.toHaveProperty("model");
    expect(installedCodex).not.toHaveProperty("model_reasoning_effort");
    expect(installedCodex).not.toHaveProperty("profiles.agentic-kit");
    expect(installedCodex).toHaveProperty("developer_instructions", expect.stringMatching(/agent_type[\s\S]*fork_turns: "none"/));
    await uninstallHost(codex);
    expect(parseToml(await readFile(codexPaths.config!, "utf8"))).toHaveProperty("mcp_servers.keep.command", "keep");
  }, 30_000);

  it("manages the OpenCode primary while preserving or explicitly overriding a custom default", async () => {
    const fixture = await fixtureEnvironment("kit-opencode-primary-");
    const options = baseOptions("opencode", "user", fixture);
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    const orchestrator = await readFile(path.join(sourceRoot, "core/orchestrator.md"), "utf8");
    const canonicalPrimary = await readFile(path.join(sourceRoot, "core/opencode-primary.md"), "utf8");
    const expectedPrimary = `${orchestrator.trim()}\n\n${canonicalPrimary.trim()}`;
    await mkdir(path.dirname(paths.config!), { recursive: true });
    await writeFile(paths.config!, '{\n  // keep this comment\n  "theme": "dark",\n  "default_agent": "custom-primary"\n}\n', "utf8");

    await installHost(options);
    const installedPrimary = parseFrontmatter(await readFile(path.join(paths.agents, "agentic-kit.md"), "utf8"));
    expect(installedPrimary.data).toMatchObject({ mode: "primary" });
    expect(installedPrimary.data).not.toHaveProperty("permission");
    expect(installedPrimary.content.trim()).toBe(expectedPrimary);
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).toMatchObject({ theme: "dark", default_agent: "custom-primary" });

    await installHost({ ...options, setDefaultAgent: true });
    const updatedPrimary = parseFrontmatter(await readFile(path.join(paths.agents, "agentic-kit.md"), "utf8"));
    expect(updatedPrimary.data).toMatchObject({ mode: "primary" });
    expect(updatedPrimary.data).not.toHaveProperty("permission");
    expect(updatedPrimary.content.trim()).toBe(expectedPrimary);
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).toHaveProperty("default_agent", "agentic-kit");
    await installHost(options);
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).toHaveProperty("default_agent", "agentic-kit");

    await uninstallHost(options);
    const restored = await readFile(paths.config!, "utf8");
    expect(restored).toContain("// keep this comment");
    expect(parseJsonc(restored)).toMatchObject({ theme: "dark", default_agent: "custom-primary" });
    await expect(readFile(path.join(paths.agents, "agentic-kit.md"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
  }, 30_000);

  it("upgrades a hash-owned OpenCode primary created before generated headers", async () => {
    const fixture = await fixtureEnvironment("kit-opencode-markerless-primary-");
    const options = baseOptions("opencode", "user", fixture);
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    const installed = await installHost(options);
    const primaryPath = path.join(paths.agents, "agentic-kit.md");
    const markerless = (await readFile(primaryPath, "utf8")).replace(/^# @generated by Agentic Coding Kit;.*\r?\n/m, "");
    await writeFile(primaryPath, markerless, "utf8");

    const installManifest = JSON.parse(await readFile(installed.manifestPath, "utf8")) as {
      files: Array<{ path: string; sha256: string }>;
    };
    const primaryEntry = installManifest.files.find((file) => path.resolve(file.path) === path.resolve(primaryPath));
    expect(primaryEntry).toBeDefined();
    primaryEntry!.sha256 = createHash("sha256").update(markerless, "utf8").digest("hex");
    await writeFile(installed.manifestPath, `${JSON.stringify(installManifest, null, 2)}\n`, "utf8");

    await expect(installHost(options)).resolves.toBeDefined();
    expect(await readFile(primaryPath, "utf8")).toContain("@generated by Agentic Coding Kit");
  }, 30_000);

  it("applies and restores permissive OpenCode permissions for every installed agent", async () => {
    const fixture = await fixtureEnvironment("kit-opencode-permissive-");
    const options = { ...baseOptions("opencode", "user", fixture), profile: "full" as const, security: "permissive" as const, yes: true };
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    await mkdir(path.dirname(paths.config!), { recursive: true });
    await writeFile(paths.config!, '{\n  // keep\n  "provider": { "custom": true },\n  "agent": { "custom": { "model": "keep" } }\n}\n', "utf8");

    const result = await installHost(options);
    const installed = parseJsonc(await readFile(paths.config!, "utf8"));
    expect(result.warnings).not.toEqual(expect.arrayContaining([expect.stringMatching(/security profile preserved/i)]));
    expect(installed).toHaveProperty("permission", OPENCODE_PERMISSIVE_PERMISSIONS);
    for (const id of ["agentic-kit", "coder", "reviewer", "test-engineer", "browser-qa"]) {
      const expected = id === "agentic-kit"
        ? OPENCODE_PERMISSIVE_PERMISSIONS
        : { ...OPENCODE_PERMISSIVE_PERMISSIONS, skill: "deny", task: "deny" };
      expect(installed).toHaveProperty(`agent.${id}.permission`, expected);
      const agent = parseFrontmatter(await readFile(path.join(paths.agents, `${id}.md`), "utf8"));
      expect(agent.data).toHaveProperty("permission", expected);
    }
    expect(installed).toHaveProperty("agent.custom.model", "keep");

    await uninstallHost(options);
    const restored = parseJsonc(await readFile(paths.config!, "utf8"));
    expect(restored).toHaveProperty("provider.custom", true);
    expect(restored).toHaveProperty("agent.custom.model", "keep");
    expect(restored).not.toHaveProperty("permission");
    expect(restored).not.toHaveProperty("agent.coder.permission");
  }, 30_000);

  it("preserves a UTF-8 BOM while updating and restoring OpenCode JSONC", async () => {
    const fixture = await fixtureEnvironment("kit-opencode-bom-");
    const options = baseOptions("opencode", "user", fixture);
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    await mkdir(path.dirname(paths.config!), { recursive: true });
    await writeFile(paths.config!, '\uFEFF{\n  // keep this comment\n  "default_agent": "custom-primary"\n}\n', "utf8");

    await installHost(options);
    expect(await readFile(paths.config!, "utf8")).toMatch(/^\uFEFF/);
    expect(parseJsonc(await readFile(paths.config!, "utf8"))).toHaveProperty("default_agent", "custom-primary");

    await installHost({ ...options, setDefaultAgent: true });
    const updated = await readFile(paths.config!, "utf8");
    expect(updated).toMatch(/^\uFEFF/);
    expect(updated).toContain("// keep this comment");
    expect(parseJsonc(updated)).toHaveProperty("default_agent", "agentic-kit");

    await uninstallHost(options);
    const restored = await readFile(paths.config!, "utf8");
    expect(restored).toMatch(/^\uFEFF/);
    expect(restored).toContain("// keep this comment");
    expect(parseJsonc(restored)).toHaveProperty("default_agent", "custom-primary");
  }, 30_000);

  it.each(["user", "project"] as const)("selects sole OpenCode JSONC and preserves comments at %s scope", async (scope) => {
    const fixture = await fixtureEnvironment(`kit-opencode-jsonc-${scope}-`);
    const configRoot = scope === "user" ? fixture.context.env.OPENCODE_CONFIG_DIR! : fixture.repo;
    const config = path.join(configRoot, "opencode.jsonc");
    await mkdir(configRoot, { recursive: true });
    await writeFile(config, '{\n  // retained setting\n  "theme": "dark"\n}\n', "utf8");

    await installHost(baseOptions("opencode", scope, fixture));

    const paths = await resolveHostPaths("opencode", scope, scope === "project" ? fixture.repo : undefined, fixture.context);
    expect(path.basename(paths.config!)).toBe("opencode.jsonc");
    expect(await readFile(config, "utf8")).toContain("// retained setting");
    expect(parseJsonc(await readFile(config, "utf8"))).toMatchObject({ theme: "dark", default_agent: "agentic-kit" });
  }, 30_000);

  it.each(["user", "project"] as const)("rejects ambiguous OpenCode config without writes at %s scope", async (scope) => {
    const fixture = await fixtureEnvironment(`kit-opencode-ambiguous-${scope}-`);
    const configRoot = scope === "user" ? fixture.context.env.OPENCODE_CONFIG_DIR! : fixture.repo;
    await mkdir(configRoot, { recursive: true });
    await writeFile(path.join(configRoot, "opencode.json"), '{"theme":"json"}\n', "utf8");
    await writeFile(path.join(configRoot, "opencode.jsonc"), '{"theme":"jsonc"}\n', "utf8");

    await expect(installHost(baseOptions("opencode", scope, fixture))).rejects.toThrow(/Ambiguous OpenCode configuration.*OPENCODE_CONFIG/i);
    const instruction = scope === "user" ? path.join(configRoot, "AGENTS.md") : path.join(fixture.repo, "AGENTS.md");
    await expect(readFile(instruction, "utf8")).rejects.toThrow();
    expect(await readFile(path.join(configRoot, "opencode.json"), "utf8")).toBe('{"theme":"json"}\n');
    expect(await readFile(path.join(configRoot, "opencode.jsonc"), "utf8")).toBe('{"theme":"jsonc"}\n');
  });

  it("rejects malformed OpenCode config before changing an existing single-host install", async () => {
    const fixture = await fixtureEnvironment("kit-opencode-malformed-update-");
    const options = baseOptions("opencode", "user", fixture);
    await installHost(options);
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    await expect(readFile(paths.instruction, "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    const agent = path.join(paths.agents, "reviewer.md");
    const agentBefore = await readFile(agent, "utf8");
    await writeFile(paths.config!, '{"default_agent":\n', "utf8");

    await expect(installHost(options)).rejects.toThrow(/malformed JSONC/i);

    expect(await readFile(paths.config!, "utf8")).toBe('{"default_agent":\n');
    await expect(readFile(paths.instruction, "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    expect(await readFile(agent, "utf8")).toBe(agentBefore);
  }, 30_000);

  it("replaces malformed OpenCode config during an explicit global reset", async () => {
    const fixture = await fixtureEnvironment("kit-opencode-malformed-reset-");
    const options = baseOptions("opencode", "user", fixture);
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    await mkdir(path.dirname(paths.config!), { recursive: true });
    await writeFile(paths.config!, '{"default_agent":\n', "utf8");

    await installHost({ ...options, clearGlobalConfig: true, yes: true });

    expect(parseJsonc(await readFile(paths.config!, "utf8"))).toEqual({ default_agent: "agentic-kit" });
  }, 30_000);

  it("rejects an OpenCode project config directory before creating managed project files", async () => {
    const fixture = await fixtureEnvironment("kit-opencode-directory-project-");
    const config = path.join(fixture.repo, "opencode.json");
    await mkdir(config, { recursive: true });

    await expect(installHost(baseOptions("opencode", "project", fixture))).rejects.toThrow(/regular file.*symlink/i);

    await expect(readFile(path.join(fixture.repo, "AGENTS.md"), "utf8")).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readdir(path.join(fixture.repo, ".opencode"))).rejects.toMatchObject({ code: "ENOENT" });
    await expect(readdir(config)).resolves.toEqual([]);
  });

  it("preserves a pre-existing agentic-kit OpenCode default across install and uninstall", async () => {
    const fixture = await fixtureEnvironment("kit-opencode-existing-default-");
    const options = baseOptions("opencode", "user", fixture);
    const paths = await resolveHostPaths("opencode", "user", undefined, fixture.context);
    await mkdir(path.dirname(paths.config!), { recursive: true });
    await writeFile(paths.config!, '{\n  // user selected this before installing the kit\n  "default_agent": "agentic-kit"\n}\n', "utf8");

    const result = await installHost(options);
    const manifest = JSON.parse(await readFile(result.manifestPath, "utf8")) as {
      configChanges: Array<{ previousExists: boolean; previousValue: unknown }>;
    };
    expect(manifest.configChanges).toContainEqual(expect.objectContaining({ previousExists: true, previousValue: "agentic-kit" }));

    await uninstallHost(options);
    const restored = await readFile(paths.config!, "utf8");
    expect(restored).toContain("// user selected this before installing the kit");
    expect(parseJsonc(restored)).toHaveProperty("default_agent", "agentic-kit");
  }, 30_000);

  it("dry-run writes nothing and malformed blocks require force", async () => {
    const fixture = await fixtureEnvironment("kit-dry-run-");
    const options = baseOptions("codex", "project", fixture);
    await installHost({ ...options, dryRun: true });
    await expect(readFile(path.join(fixture.repo, "AGENTS.md"), "utf8")).rejects.toThrow();
    await writeFile(path.join(fixture.repo, "AGENTS.md"), "user\n<!-- agentic-coding-kit:start -->\nbroken\n", "utf8");
    await expect(installHost(options)).rejects.toThrow(/malformed|duplicate/i);
    await installHost({ ...options, force: true });
    expect(await readFile(path.join(fixture.repo, "AGENTS.md"), "utf8")).toBe("user\n");
  }, 30_000);
});

function baseOptions(host: Host, scope: "user" | "project", fixture: Awaited<ReturnType<typeof fixtureEnvironment>>): InstallOptions {
  return { repoRoot: sourceRoot, host, scope, repo: scope === "project" ? fixture.repo : undefined, profile: "core", security: "preserve", memory: "preserve", commands: "auto", setDefaultAgent: false, dryRun: false, force: false, yes: false, verbose: false, pathContext: fixture.context };
}

async function fixtureEnvironment(prefix: string): Promise<{ home: string; repo: string; context: PathEnvironment }> {
  const root = await mkdtemp(path.join(tmpdir(), prefix));
  const home = path.join(root, "home space Ω");
  const repo = path.join(root, "repo space Ω");
  await mkdir(home, { recursive: true });
  await mkdir(repo, { recursive: true });
  await execFile("git", ["init", "--quiet"], { cwd: repo });
  const env = { ...process.env, CODEX_HOME: path.join(home, "codex"), CLAUDE_CONFIG_DIR: path.join(home, "claude"), OPENCODE_CONFIG_DIR: path.join(home, "opencode"), OPENCODE_CONFIG: undefined, COPILOT_HOME: path.join(home, "copilot") };
  return { home, repo, context: { home, platform: process.platform, env } };
}
