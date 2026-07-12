import { mkdir, mkdtemp, readFile, readdir, rename, symlink, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { allAgents, loadManifest, validateManifestSchema, validateManifestSemantics } from "../src/manifest.js";
import { findBrokenLocalMarkdownLinks } from "../src/links.js";
import { parseFrontmatter, parseJsonc, parseToml, parseYaml, serializeFrontmatter, serializeToml, serializeYaml } from "../src/parsers.js";
import {
  evaluateCompletion,
  isEvidenceFresh,
  normalizeFailureSignature,
  recordUnsuccessfulRepair,
  validateHandoff,
} from "../src/policy.js";
import { checkGeneratedDrift, loadSkillResources, renderArtifacts, writeGenerated } from "../src/render.js";
import { resolveContainedPath, resolveExistingContainedPath, setPathOperationHookForTests } from "../src/paths.js";
import { validateCanonicalPrompts, validateGeneratedArtifacts } from "../src/validate.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

describe("parser-backed formats", () => {
  it("round-trips YAML, TOML, JSONC, and Markdown frontmatter", () => {
    const yamlValue = { name: "build", nested: { enabled: true }, values: ["a", "b"] };
    expect(parseYaml(serializeYaml(yamlValue))).toEqual(yamlValue);
    const tomlValue = { name: "reviewer", description: "Independent: reviewer", agents: { max_depth: 1 } };
    expect(parseToml(serializeToml(tomlValue))).toEqual(tomlValue);
    expect(parseJsonc('{ // retained\n "model": "inherit",\n}')).toEqual({ model: "inherit" });
    expect(() => parseJsonc('{ "broken": }')).toThrow(/Invalid JSONC/);
    const markdown = serializeFrontmatter({ name: "wiki", description: "Maintain repository knowledge." }, "# Wiki\n\nBody");
    expect(parseFrontmatter(markdown)).toMatchObject({ data: { name: "wiki" }, content: expect.stringContaining("# Wiki") });
  });
});

describe("canonical manifest and prompts", () => {
  it("passes schema, source, and semantic validation with exact rosters", async () => {
    const manifest = await loadManifest(root);
    expect(manifest.skills.map((item) => item.id).sort()).toEqual(["analyze", "build", "design", "pr-ready", "review", "threat-model", "wiki"]);
    expect(manifest.agents.map((item) => item.id).sort()).toEqual(["coder", "diagnostician", "repo-scout", "reviewer", "sage", "security-reviewer", "test-engineer"]);
    expect(manifest.packs.ui.agents.map((item) => item.id).sort()).toEqual(["browser-qa", "ui-critic"]);
    expect(allAgents(manifest)).toHaveLength(9);
  });

  it("enforces permissions and keeps portable sources model-neutral", async () => {
    const manifest = await loadManifest(root);
    const tester = manifest.agents.find((item) => item.id === "test-engineer")!;
    expect(tester.permission_class).toBe("test-write");
    expect(tester.write_scope?.sort()).toEqual(["fixtures", "test-utilities", "tests"]);
    for (const agent of allAgents(manifest).filter((item) => item.permission_class === "read-only")) expect(agent.write_scope).toBeUndefined();
    expect(JSON.stringify(manifest)).not.toMatch(/gpt-5\.6-(luna|terra|sol)/);
  });

  it("rejects a portable manifest that attempts to embed a provider model mapping", async () => {
    const manifest = await loadManifest(root);
    const schema = JSON.parse(await readFile(path.join(root, "core/schemas/manifest.schema.json"), "utf8"));
    const mapped = structuredClone(manifest) as any;
    mapped.model_profiles = { codex: { deep: { model: "gpt-5.6-sol", reasoning: "medium" } } };
    expect(() => validateManifestSchema(mapped, schema)).toThrow(/additional properties/);
  });

  it("rejects canonical source paths that escape the repository root", async () => {
    const manifest = await loadManifest(root);
    const sandbox = await mkdtemp(path.join(tmpdir(), "kit-manifest-path-"));
    const outsideSource = path.join(sandbox, "outside-skill.md");
    await writeFile(outsideSource, "# Outside source\n", "utf8");
    const unsafe = structuredClone(manifest);
    unsafe.skills[0]!.source = path.relative(root, outsideSource);

    await expect(validateManifestSemantics(root, unsafe)).rejects.toThrow(/outside|escape|repository root/i);
  });

  it("rejects absolute, drive, UNC, drive-relative, traversal, and sibling-prefix paths", () => {
    const sandbox = path.join(tmpdir(), "kit-boundary");
    for (const candidate of [path.resolve(sandbox, "absolute.md"), "C:\\absolute.md", "\\\\server\\share\\file.md", "C:drive-relative.md", "../sibling/file.md", "..\\sibling-prefix\\file.md"]) {
      expect(() => resolveContainedPath(sandbox, candidate, "repository root")).toThrow(/absolute|escape|traversal|outside/i);
    }
  });

  it("rejects source symlinks and bounds canonical skill resource ingestion", async () => {
    const sandbox = await mkdtemp(path.join(tmpdir(), "kit-sources-"));
    const skillRoot = path.join(sandbox, "core", "skills", "build");
    await mkdir(path.join(skillRoot, "node_modules"), { recursive: true });
    await writeFile(path.join(skillRoot, "SKILL.md"), "---\nname: build\ndescription: test\n---\n", "utf8");
    await writeFile(path.join(skillRoot, ".env"), "SECRET=not-rendered\n", "utf8");
    await writeFile(path.join(skillRoot, "node_modules", "secret.md"), "secret\n", "utf8");
    expect((await loadSkillResources(sandbox, "build", "core/skills/build/SKILL.md")).map((item) => item.relativePath)).toEqual(["SKILL.md"]);
    await writeFile(path.join(sandbox, "outside.md"), "outside\n", "utf8");
    const link = path.join(skillRoot, "linked.md");
    if (await tryDirectoryOrFileLink(path.join(sandbox, "outside.md"), link, "file")) {
      await expect(resolveExistingContainedPath(sandbox, "core/skills/build/linked.md", "repository root")).rejects.toThrow(/symlink|junction/i);
      await expect(loadSkillResources(sandbox, "build", "core/skills/build/SKILL.md")).rejects.toThrow(/symlink|junction/i);
      await unlink(link);
    }
    await writeFile(path.join(skillRoot, "huge.md"), "x".repeat(512 * 1024 + 1), "utf8");
    await expect(loadSkillResources(sandbox, "build", "core/skills/build/SKILL.md")).rejects.toThrow(/exceeds/);
  });

  it("keeps canonical prompts model-neutral and encodes core invariants", async () => {
    const manifest = await loadManifest(root);
    await expect(validateCanonicalPrompts(root, manifest)).resolves.toBeUndefined();
    const orchestrator = await readFile(path.join(root, "core/orchestrator.md"), "utf8");
    const normalized = orchestrator.replace(/\s+/g, " ");
    for (const phrase of ["main-session orchestrator", "dynamic task packet", "live workspace", "compact returned handoff", "smallest reliable loop", "cheap relevant machine checks before independent model review", "test-engineer", "last relevant edit", "Normal build, design, analyze, and review work never modifies `.wiki`"]) expect(normalized).toContain(phrase);
    expect(orchestrator).toMatch(/Delegation is optional, not a quota/);
    expect(orchestrator).toMatch(/direct inline change/);
    expect(orchestrator).toMatch(/Do not continue spawning agents merely to complete a ceremony/);
    expect(orchestrator).toMatch(/User testing is\s+valuable external evidence/);
    expect(orchestrator).toMatch(/`INLINE`[\s\S]*`STANDARD`[\s\S]*`DEEP`/);
    expect(orchestrator).toMatch(/Every agent returns to you/);
    expect(orchestrator).toMatch(/at most two failed repaired results/);
    const buildSkill = await readFile(path.join(root, "core/skills/build/SKILL.md"), "utf8");
    const designSkill = await readFile(path.join(root, "core/skills/design/SKILL.md"), "utf8");
    expect(buildSkill).toMatch(/playbooks are not mandatory pipelines/i);
    expect(designSkill).toMatch(/`INLINE DESIGN`[\s\S]*`REVIEWED DESIGN`/);
    const reviewer = await readFile(path.join(root, "core/agents/reviewer.md"), "utf8");
    const coder = await readFile(path.join(root, "core/agents/coder.md"), "utf8");
    const tester = await readFile(path.join(root, "core/agents/test-engineer.md"), "utf8");
    const threatModel = await readFile(path.join(root, "core/skills/threat-model/SKILL.md"), "utf8");
    const securityReviewer = await readFile(path.join(root, "core/agents/security-reviewer.md"), "utf8");
    expect(reviewer).toContain("unverified claims");
    expect(coder).toMatch(/minimum\s+behavior tests/);
    expect(tester).toMatch(/may not edit\s+production code/);
    expect(threatModel).toMatch(/`FOCUSED`[\s\S]*`FULL`[\s\S]*`INCREMENTAL`/);
    expect(threatModel).toMatch(/Remain read-only unless the user explicitly approves a report target path/);
    expect(threatModel).toMatch(/transition requested fixes[\s\S]*`build` skill/i);
    expect(securityReviewer).toMatch(/Return one Security Review Report to the main\s+orchestrator/);
  });
});

describe("native adapter generation", () => {
  it("refuses generated destinations that escape the render root", async () => {
    const sandbox = await mkdtemp(path.join(tmpdir(), "kit-render-path-"));
    const target = path.join(sandbox, "checkout");
    const escaped = path.join(sandbox, "escaped.md");

    await expect(writeGenerated(target, [{
      path: "../escaped.md",
      content: `<!-- @generated by Agentic Coding Kit v6; source=test -->\n`,
      sourceId: "test:escape",
    }])).rejects.toThrow(/outside|escape|render root/i);
    await expect(readFile(escaped, "utf8")).rejects.toThrow();
  });

  it("rejects destination junction ancestry before outside parent creation", async () => {
    const sandbox = await mkdtemp(path.join(tmpdir(), "kit-destination-link-"));
    const target = path.join(sandbox, "checkout");
    const outside = path.join(sandbox, "outside");
    await mkdir(target);
    await mkdir(outside);
    const adapterLink = path.join(target, "adapters");
    if (await tryDirectoryOrFileLink(outside, adapterLink, "dir")) {
      await expect(writeGenerated(target, [{ path: "adapters/copilot/deep/file.md", content: "safe", sourceId: "test" }])).rejects.toThrow(/symlink|junction/i);
      await expect(readFile(path.join(outside, "copilot", "deep", "file.md"), "utf8")).rejects.toThrow();
      await expect(readdir(outside)).resolves.toEqual([]);
    }
  });

  it("detects a deterministic parent swap before atomic replacement", async () => {
    const sandbox = await mkdtemp(path.join(tmpdir(), "kit-parent-swap-"));
    const target = path.join(sandbox, "checkout");
    const parent = path.join(target, "adapters", "copilot");
    const backup = path.join(target, "adapters", "copilot-original");
    const outside = path.join(sandbox, "outside");
    await mkdir(parent, { recursive: true });
    await mkdir(outside);
    let linked = false;
    setPathOperationHookForTests(async (stage) => {
      if (stage !== "before-final-write-check") return;
      await rename(parent, backup);
      linked = await tryDirectoryOrFileLink(outside, parent, "dir");
      if (!linked) await mkdir(parent);
    });
    try {
      await expect(writeGenerated(target, [{ path: "adapters/copilot/file.md", content: "safe", sourceId: "test" }])).rejects.toThrow();
      await expect(readFile(path.join(outside, "file.md"), "utf8")).rejects.toThrow();
    } finally {
      setPathOperationHookForTests(undefined);
    }
  });

  it("handles core/full packs and emits parseable marked artifacts", async () => {
    const manifest = await loadManifest(root);
    const core = await renderArtifacts(root, manifest, { installProfile: "core", commands: false });
    const full = await renderArtifacts(root, manifest, { installProfile: "full", commands: true });
    expect(core.some((file) => /browser-qa/.test(file.path))).toBe(false);
    expect(core.some((file) => file.path.endsWith("security-reviewer.agent.md"))).toBe(true);
    expect(full.some((file) => file.path.endsWith("browser-qa.toml"))).toBe(true);
    expect(full.some((file) => file.path.endsWith("security-reviewer.agent.md"))).toBe(true);
    expect(full.filter((file) => file.path.startsWith("adapters/opencode/commands/"))).toHaveLength(7);
    expect(() => validateGeneratedArtifacts(full)).not.toThrow();
    expect(findBrokenLocalMarkdownLinks(full)).toEqual([]);

    for (const skill of manifest.skills) {
      const canonicalRoot = path.join(root, path.dirname(skill.source));
      const canonicalFiles = (await readdir(canonicalRoot, { recursive: true, withFileTypes: true }))
        .filter((entry) => entry.isFile())
        .map((entry) => path.relative(canonicalRoot, path.join(entry.parentPath, entry.name)).split(path.sep).join("/"))
        .sort();
      for (const host of ["codex", "claude", "opencode", "copilot"]) {
        const rendered = full
          .filter((file) => file.path.startsWith(`adapters/${host}/skills/${skill.id}/`))
          .map((file) => file.path.slice(`adapters/${host}/skills/${skill.id}/`.length))
          .sort();
        expect(rendered).toEqual(canonicalFiles);
      }
    }
  });

  it("uses host-native fields and provider semantics", async () => {
    const manifest = await loadManifest(root);
    const files = await renderArtifacts(root, manifest, { installProfile: "full", commands: true });
    const codex = parseToml<Record<string, unknown>>(files.find((file) => file.path === "adapters/codex/agents/reviewer.toml")!.content);
    expect(codex).toMatchObject({ name: "reviewer", sandbox_mode: "read-only" });
    expect(codex).not.toHaveProperty("model");
    expect(codex).not.toHaveProperty("model_reasoning_effort");
    const claude = parseFrontmatter(files.find((file) => file.path === "adapters/claude/agents/reviewer.md")!.content);
    expect(claude.data).toMatchObject({ name: "reviewer", model: "inherit", permissionMode: "plan" });
    expect(claude.data).not.toHaveProperty("memory");
    const opencode = parseFrontmatter(files.find((file) => file.path === "adapters/opencode/agents/reviewer.md")!.content);
    expect(opencode.data).toMatchObject({ mode: "subagent", permission: { edit: "deny" } });
    expect(opencode.data).not.toHaveProperty("tools");
    expect(opencode.data).not.toHaveProperty("model");
    const command = parseFrontmatter(files.find((file) => file.path === "adapters/opencode/commands/build.md")!.content);
    expect(command.data).not.toHaveProperty("agent");
    expect(command.content).toContain("$ARGUMENTS");
    const copilot = parseFrontmatter(files.find((file) => file.path === "adapters/copilot/agents/reviewer.agent.md")!.content);
    expect(copilot.data).toEqual({ name: "reviewer", description: expect.any(String), tools: ["read", "search"] });
    const copilotCoder = parseFrontmatter(files.find((file) => file.path === "adapters/copilot/agents/coder.agent.md")!.content);
    expect(copilotCoder.data.tools).toEqual(["read", "search", "edit", "execute"]);
    const copilotTester = parseFrontmatter(files.find((file) => file.path === "adapters/copilot/agents/test-engineer.agent.md")!.content);
    expect(copilotTester.data.tools).toEqual(["read", "search", "edit", "execute"]);
    expect(copilotTester.content).toMatch(/may not edit\s+production code/);
    expect(files.find((file) => file.path === "adapters/copilot/instructions.md")!.content).toContain("inspect skills with `/skills`");
  });

  it("emits model-neutral agents and deterministic drift checks", async () => {
    const manifest = await loadManifest(root);
    const files = await renderArtifacts(root, manifest, { installProfile: "full", commands: true });
    expect(parseToml(files.find((file) => file.path.endsWith("codex/agents/coder.toml"))!.content)).not.toHaveProperty("model");
    const target = await mkdtemp(path.join(tmpdir(), "kit-render-"));
    await writeGenerated(target, files);
    expect(await checkGeneratedDrift(target, files)).toEqual([]);
    for (const file of files) {
      const filePath = path.join(target, file.path);
      await writeFile(filePath, (await readFile(filePath, "utf8")).replace(/\r?\n/g, "\r\n"), "utf8");
    }
    expect(await checkGeneratedDrift(target, files)).toEqual([]);
    const first = files.find((file) => !file.path.endsWith(".agentic-kit-generated.json"))!;
    const disk = await readFile(path.join(target, first.path), "utf8");
    expect(disk.charCodeAt(0)).not.toBe(0xfeff);
    await writeFile(path.join(target, first.path), `${disk}\ndrift`, "utf8");
    expect(await checkGeneratedDrift(target, files)).toEqual([`conflict:${first.path}`]);
  });

  it("reports and removes only marker-owned stale outputs across profile changes", async () => {
    const manifest = await loadManifest(root);
    const full = await renderArtifacts(root, manifest, { installProfile: "full", commands: true });
    const core = await renderArtifacts(root, manifest, { installProfile: "core", commands: false });
    const target = await mkdtemp(path.join(tmpdir(), "kit-reconcile-"));
    await writeGenerated(target, full);
    const unowned = path.join(target, "adapters", "copilot", "user-owned.agent.md");
    await writeFile(unowned, "<!-- @generated by Agentic Coding Kit v6; source=fake; sourceId=fake -->\n# User-owned adapter\n", "utf8");
    const drift = await checkGeneratedDrift(target, core);
    expect(drift).toContain("adapters/copilot/agents/browser-qa.agent.md");
    expect(drift).toContain("adapters/opencode/commands/build.md");
    await writeGenerated(target, core);
    expect(await checkGeneratedDrift(target, core)).toEqual([]);
    await expect(readFile(unowned, "utf8")).resolves.toContain("User-owned");
    await expect(readFile(path.join(target, "adapters", "copilot", "agents", "browser-qa.agent.md"), "utf8")).rejects.toThrow();
    await expect(readFile(path.join(target, "adapters", "opencode", "commands", "build.md"), "utf8")).rejects.toThrow();
  });

  it("refuses to delete a locally modified stale generated file", async () => {
    const manifest = await loadManifest(root);
    const full = await renderArtifacts(root, manifest, { installProfile: "full", commands: true });
    const core = await renderArtifacts(root, manifest, { installProfile: "core", commands: false });
    const target = await mkdtemp(path.join(tmpdir(), "kit-stale-conflict-"));
    await writeGenerated(target, full);
    const stale = path.join(target, "adapters", "copilot", "agents", "browser-qa.agent.md");
    await writeFile(stale, `${await readFile(stale, "utf8")}\nlocal edit\n`, "utf8");
    expect(await checkGeneratedDrift(target, core)).toContain("conflict:adapters/copilot/agents/browser-qa.agent.md");
    await expect(writeGenerated(target, core)).rejects.toThrow(/conflict|refusing/i);
    await expect(readFile(stale, "utf8")).resolves.toContain("local edit");
  });

  it("refuses to overwrite a locally modified expected managed file", async () => {
    const manifest = await loadManifest(root);
    const files = await renderArtifacts(root, manifest, { installProfile: "full", commands: true });
    const target = await mkdtemp(path.join(tmpdir(), "kit-expected-conflict-"));
    await writeGenerated(target, files);
    const managed = path.join(target, "adapters", "copilot", "agents", "reviewer.agent.md");
    const locallyModified = `${await readFile(managed, "utf8")}\nlocal expected edit\n`;
    await writeFile(managed, locallyModified, "utf8");

    expect(await checkGeneratedDrift(target, files)).toContain("conflict:adapters/copilot/agents/reviewer.agent.md");
    await expect(writeGenerated(target, files)).rejects.toThrow(/expected-file conflict|refusing render/i);
    await expect(readFile(managed, "utf8")).resolves.toBe(locallyModified);
  });
});

describe("deterministic orchestration policy helpers", () => {
  it("normalizes repeated signatures", () => {
    const first = normalizeFailureSignature({ scenario: " npm test ", failingCase: "case A", primaryError: " Timeout ", changedPaths: ["b.ts", "a.ts"] });
    const second = normalizeFailureSignature({ scenario: "npm   test", failingCase: "case A", primaryError: "Timeout", changedPaths: ["a.ts", "b.ts"] });
    expect(first).toBe(second);
  });

  it("stops repair spawning after two completed repairs fail their next gates", () => {
    const first = recordUnsuccessfulRepair(0);
    const second = recordUnsuccessfulRepair(first.attempts);
    expect(first).toEqual({ attempts: 1, limit: 2, mayContinue: true });
    expect(second).toEqual({ attempts: 2, limit: 2, mayContinue: false });
  });

  it("validates handoff shape without treating claims as evidence", () => {
    expect(validateHandoff("scout", {
      status: "CLEAR",
      missionAnswered: "Found ownership and nearest tests",
      relevantFlow: "src/api.ts calls the transport",
      implementationSurface: ["src/api.ts", "tests/api.test.ts"],
      verification: ["npm test -- api"],
    })).toEqual({ valid: true, missing: [] });
    expect(validateHandoff("review", {
      verdict: "PASS",
      contractAssessment: "Acceptance examples are covered",
      findings: [],
    })).toEqual({ valid: true, missing: [] });
    expect(validateHandoff("test-charter", {
      contractBehaviors: ["returns the transport result"],
      existingEvidence: [],
      highestValueGaps: [],
      chosenTestLevel: "unit — lowest reliable level",
    })).toEqual({ valid: true, missing: [] });
    expect(validateHandoff("test", {
      outcome: "PASS",
      evidence: [{ command: "npm test", result: "pass" }],
    })).toEqual({ valid: true, missing: [] });
    expect(validateHandoff("test", {
      outcome: "CODE_DEFECT",
      evidence: [{ command: "npm test", result: "fail" }],
    })).toEqual({ valid: false, missing: ["defectEvidence"] });
    expect(validateHandoff("test", {
      outcome: "CODE_DEFECT",
      evidence: [{ command: "npm test", result: "fail" }],
      defectEvidence: {
        failingTest: "returns propagated failure",
        expected: "error",
        actual: "success",
        productionPath: "src/api.ts",
        reproduction: "npm test -- api",
      },
    })).toEqual({ valid: true, missing: [] });
    expect(validateHandoff("coder", { status: "DONE", implemented: "behavior" })).toEqual({
      valid: false,
      missing: ["changed", "evidence"],
    });
    expect(validateHandoff("coder", {
      status: "CONTRACT_GAP",
      implemented: "partial behavior",
      changed: [],
      evidence: [],
    })).toEqual({ valid: false, missing: ["contractGap"] });
  });

  it("binds evidence and completion to the current revision", () => {
    expect(isEvidenceFresh({ evidenceRevision: "tree-a", currentRevision: "tree-a" })).toBe(true);
    expect(isEvidenceFresh({ evidenceRevision: "tree-a", currentRevision: "tree-b" })).toBe(false);
    expect(evaluateCompletion({
      requestSatisfied: true,
      blockingFindings: 0,
      materialUnknowns: 0,
      evidenceRevision: "tree-a",
      currentRevision: "tree-a",
    })).toEqual({ ready: true, reasons: [] });
    expect(evaluateCompletion({
      requestSatisfied: false,
      blockingFindings: 1,
      materialUnknowns: 1,
      evidenceRevision: "tree-a",
      currentRevision: "tree-b",
    })).toEqual({
      ready: false,
      reasons: [
        "requested outcome is not satisfied",
        "blocking findings remain",
        "material unknowns remain",
        "verification evidence is stale or missing",
      ],
    });
  });
});

async function tryDirectoryOrFileLink(target: string, linkPath: string, kind: "dir" | "file"): Promise<boolean> {
  try {
    await symlink(target, linkPath, kind === "dir" && process.platform === "win32" ? "junction" : kind);
    return true;
  } catch (error) {
    if (["EPERM", "EACCES", "ENOTSUP"].includes((error as NodeJS.ErrnoException).code ?? "")) return false;
    throw error;
  }
}
