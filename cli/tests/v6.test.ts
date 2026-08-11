import { mkdir, mkdtemp, readFile, readdir, rename, symlink, unlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { allAgents, loadManifest, validateManifestSchema, validateManifestSemantics } from "../src/manifest.js";
import { findBrokenLocalMarkdownLinks } from "../src/links.js";
import { getTomlRootString, setTomlRootString } from "../src/config-merge.js";
import { parseFrontmatter, parseJsonc, parseToml, parseYaml, serializeFrontmatter, serializeToml, serializeYaml } from "../src/parsers.js";
import {
  evaluateCompletion,
  isEvidenceFresh,
  normalizeFailureSignature,
  recordUnsuccessfulRepair,
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
    expect(parseJsonc('\ufeff{"model":"inherit"}')).toEqual({ model: "inherit" });
    expect(() => parseJsonc('{ "broken": }')).toThrow(/Invalid JSONC/);
    const markdown = serializeFrontmatter({ name: "wiki", description: "Maintain repository knowledge." }, "# Wiki\n\nBody");
    expect(parseFrontmatter(markdown)).toMatchObject({ data: { name: "wiki" }, content: expect.stringContaining("# Wiki") });
  });

  it("updates and restores Codex root developer instructions without rewriting other TOML", () => {
    const source = '# keep\ndeveloper_instructions = """old\npreference"""\n\n[mcp_servers.keep]\ncommand = "keep"\n';
    const updated = setTomlRootString(source, "developer_instructions", "old preference\n\nACK primary");
    expect(getTomlRootString(updated, "developer_instructions")).toEqual({ exists: true, value: "old preference\n\nACK primary" });
    expect(updated).toContain("# keep");
    expect(updated).toContain('[mcp_servers.keep]\ncommand = "keep"');
    const restored = setTomlRootString(updated, "developer_instructions", "old\npreference");
    expect(getTomlRootString(restored, "developer_instructions")).toEqual({ exists: true, value: "old\npreference" });
  });
});

describe("canonical manifest and prompts", () => {
  it("passes schema, source, and semantic validation with exact rosters", async () => {
    const manifest = await loadManifest(root);
    expect(manifest.skills.map((item) => item.id).sort()).toEqual(["analyze", "architecture", "build", "design", "experiment", "grill", "pr-ready", "review", "threat-model", "wiki"]);
    expect(manifest.agents.map((item) => item.id).sort()).toEqual(["architect", "coder", "diagnostician", "repo-scout", "reviewer", "sage", "security-reviewer", "test-engineer"]);
    expect(manifest.packs.ui.agents.map((item) => item.id).sort()).toEqual(["browser-qa", "ui-critic"]);
    expect(allAgents(manifest)).toHaveLength(10);
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

  it("applies canonical prompt validation to the OpenCode primary", async () => {
    const manifest = structuredClone(await loadManifest(root));
    const sandbox = await mkdtemp(path.join(tmpdir(), "kit-opencode-primary-validation-"));
    await writeFile(path.join(sandbox, "safe.md"), "# Safe prompt\n", "utf8");
    await writeFile(path.join(sandbox, "opencode-primary.md"), "Use gpt-5.6-sol\n", "utf8");
    manifest.instruction_fragments.orchestrator = "safe.md";
    manifest.instruction_fragments.opencode_primary = "opencode-primary.md";
    for (const skill of manifest.skills) skill.source = "safe.md";
    for (const agent of allAgents(manifest)) agent.source = "safe.md";

    await expect(validateCanonicalPrompts(sandbox, manifest)).rejects.toThrow(/opencode-primary.*provider model ID/i);
  });

  it("enforces prompt budgets", async () => {
    const manifest = structuredClone(await loadManifest(root));
    const sandbox = await mkdtemp(path.join(tmpdir(), "kit-prompt-budget-"));
    await writeFile(path.join(sandbox, "safe.md"), "# Safe prompt\n", "utf8");
    await writeFile(path.join(sandbox, "orchestrator.md"), "word ".repeat(851), "utf8");
    manifest.instruction_fragments.orchestrator = "orchestrator.md";
    manifest.instruction_fragments.opencode_primary = "safe.md";
    for (const skill of manifest.skills) skill.source = "safe.md";
    for (const agent of allAgents(manifest)) agent.source = "safe.md";
    await expect(validateCanonicalPrompts(sandbox, manifest)).rejects.toThrow(/orchestrator.*prompt budget/i);
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

  it("accepts the shipped canonical prompt set", async () => {
    const manifest = await loadManifest(root);
    await expect(validateCanonicalPrompts(root, manifest)).resolves.toBeUndefined();
  });

  it("encodes the primary-led three-object build flow and bounded review loop", async () => {
    const resources = await loadSkillResources(root, "build", "core/skills/build/SKILL.md");
    expect(resources.map((item) => item.relativePath)).toEqual(["SKILL.md"]);

    const build = await readFile(path.join(root, "core/skills/build/SKILL.md"), "utf8");
    const coder = await readFile(path.join(root, "core/agents/coder.md"), "utf8");
    const orchestrator = await readFile(path.join(root, "core/orchestrator.md"), "utf8");
    const scout = await readFile(path.join(root, "core/agents/repo-scout.md"), "utf8");
    const reviewer = await readFile(path.join(root, "core/agents/reviewer.md"), "utf8");
    const tester = await readFile(path.join(root, "core/agents/test-engineer.md"), "utf8");
    const security = await readFile(path.join(root, "core/agents/security-reviewer.md"), "utf8");
    const flow = `${orchestrator}\n${build}`.replace(/\s+/g, " ");
    const prompts = `${flow}\n${scout}\n${coder}\n${reviewer}\n${tester}`;

    // Object flow: the primary explores, optionally scouts, then owns one shared contract.
    expect(flow).toMatch(/primary[\s\S]*(?:explore|inspect)[\s\S]*relevant live source/i);
    expect(flow).toMatch(/optional(?:ly)?[\s\S]*(?:Repository )?(?:Repo )?Scout/i);
    expect(flow).toMatch(/exactly (?:these )?three shared (?:assignment )?objects/i);
    expect(flow).toMatch(/GOAL[\s\S]*ACCEPTANCE[\s\S]*PLAN/i);
    expect(flow).toMatch(/sole shared assignment objects/i);
    expect(flow).toMatch(/Do not (?:create|add) separate shared sections for paths, decisions, proof, Scout facts, constraints,[\s\S]*repository summaries/i);
    expect(flow).toMatch(/unchanged[\s\S]*(?:Coder|implementation)[\s\S]*(?:Test Engineer|testing)[\s\S]*(?:Reviewer|review)[\s\S]*repair/i);

    // Focused discovery supplies repository facts, never a proposed solution.
    for (const concept of ["relevant files", "existing behavior", "repository patterns", "likely focused tests", "generated boundaries"]) {
      expect(scout.toLowerCase()).toContain(concept);
    }
    expect(scout).toMatch(/Do not[\s\S]*(?:design the solution|prescribe changes|choose an architecture)/i);

    // Coder gets the immutable objects, can follow live source, and reports exact outcomes.
    expect(coder).toMatch(/contains only the unchanged GOAL, numbered ACCEPTANCE, and PLAN/i);
    expect(coder).toMatch(/Inspect all relevant live source/i);
    expect(coder).toMatch(/adapt[\s\S]*details when current source requires/i);
    expect(coder).toMatch(/report any material departure\s+from PLAN/i);
    expect(coder).toMatch(/Do not change GOAL or[\s\S]*ACCEPTANCE/i);
    expect(coder).toMatch(/`COMPLETE` or `BLOCKED`[\s\S]*implementation summary[\s\S]*exact changed path[\s\S]*relevant commands[\s\S]*limitations/i);

    // Review is independent, binary per criterion, evidence-sensitive, and narrowly blocking.
    expect(reviewer).toMatch(/same unchanged[\s\S]*GOAL[\s\S]*ACCEPTANCE[\s\S]*PLAN/i);
    expect(reviewer).toMatch(/live base-to-candidate diff and every complete changed file/i);
    expect(reviewer).toMatch(/For each acceptance criterion[\s\S]*exactly one state: `PASS` or `BLOCKED`/i);
    expect(reviewer).toMatch(/Missing decisive evidence for important\s+changed behavior is `BLOCKED`/i);
    for (const cause of ["unmet acceptance criterion", "realistic demonstrated bug", "violated repository invariant", "material maintainability regression"]) {
      expect(reviewer.toLowerCase()).toContain(cause);
    }
    expect(reviewer).toMatch(/Do not block on preferences, speculative edges, optional cleanup, or invented[\s\S]*requirements/i);
    expect(reviewer).toMatch(/at most three grouped material findings/i);
    expect(prompts).not.toContain(["UN", "PROVEN"].join(""));

    // Test hardening is conditional and minimal rather than another mandatory gate.
    expect(tester).toMatch(/only when[\s\S]*important acceptance criterion[\s\S]*lacks convincing durable proof/i);
    expect(tester).toMatch(/same unchanged[\s\S]*GOAL[\s\S]*ACCEPTANCE[\s\S]*PLAN/i);
    expect(tester).toMatch(/minimum valuable\s+behavioral tests/i);
    expect(tester).toMatch(/Do not add[\s\S]*broad matrices[\s\S]*incidental-wording checks[\s\S]*duplicated coverage/i);
    expect(tester).toMatch(/Do not replace primary verification or the Reviewer/i);

    // Repair is evidence-led, bounded, and always followed by a complete fresh review.
    expect(flow).toMatch(/validates? (?:Reviewer )?findings[\s\S]*rejects?[\s\S]*speculative edges[\s\S]*scope-expanding/i);
    expect(flow).toMatch(/supported[\s\S]*blocking evidence[\s\S]*repair Coder[\s\S]*same unchanged GOAL, ACCEPTANCE, and PLAN/i);
    expect(flow).toMatch(/Rerun affected proof[\s\S]*fresh Reviewer[\s\S]*(?:complete GOAL|whole GOAL)[\s\S]*every (?:ACCEPTANCE|acceptance) criterion/i);
    expect(flow).toMatch(/two[\s\S]*unsuccessful repair/i);

    // Wiki context is bounded navigation and does not alter the three-object handoff.
    for (const prompt of [orchestrator, scout, coder, reviewer, tester, security]) {
      expect(prompt).toMatch(/nearest applicable[\s\S]*\.wiki\/index\.md/i);
      expect(prompt).toMatch(/authoritative live source|live source, which is authoritative/i);
      expect(prompt).toMatch(/material\s+drift/i);
      expect(prompt).toMatch(/never edit\s+`?\.wiki`?/i);
    }
    expect(scout).toMatch(/repository-map and engineering[\s\S]*focus discovery/i);
    expect(coder).toMatch(/coding[\s\S]*engineering[\s\S]*testing/i);
    expect(reviewer).toMatch(/reviewing[\s\S]*engineering, coding, and[\s\S]*testing[\s\S]*Never block from wiki prose alone/i);
    expect(tester).toMatch(/relevant testing sections/i);
    expect(security).toMatch(/security[\s\S]*engineering-boundary[\s\S]*Wiki prose alone cannot support a finding/i);
  });

  it("propagates bounded wiki navigation from canonical prompts to adapters", async () => {
    const manifest = await loadManifest(root);
    const files = await renderArtifacts(root, manifest, { installProfile: "core", commands: false });
    for (const role of ["coder", "repo-scout", "reviewer", "test-engineer", "security-reviewer"]) {
      const rendered = files.filter((file) => file.path.includes(`/agents/${role}.`) || file.path.endsWith(`/agents/${role}.md`));
      expect(rendered).toHaveLength(4);
      for (const file of rendered) expect(file.content).toMatch(/nearest applicable[\s\S]*\.wiki\/index\.md/i);
    }
    for (const host of ["claude", "codex", "copilot", "opencode"]) {
      expect(files.find((file) => file.path === `adapters/${host}/instructions.md`)?.content).toMatch(/nearest applicable[\s\S]*\.wiki\/index\.md/i);
    }
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
    expect(full.filter((file) => file.path.startsWith("adapters/opencode/commands/"))).toHaveLength(10);
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
    expect(files.find((file) => file.path === "adapters/codex/instructions.md")!.content).toMatch(/agent_type[\s\S]*fork_turns: "none"/);
    const claude = parseFrontmatter(files.find((file) => file.path === "adapters/claude/agents/reviewer.md")!.content);
    expect(claude.data).toMatchObject({ name: "reviewer", model: "inherit", permissionMode: "plan" });
    expect(claude.data).not.toHaveProperty("memory");
    const opencode = parseFrontmatter(files.find((file) => file.path === "adapters/opencode/agents/reviewer.md")!.content);
    expect(opencode.data).toMatchObject({ mode: "subagent", permission: { edit: "deny", skill: "deny", task: "deny" } });
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
    expect(copilotTester.content).toMatch(/never production/);
    expect(files.find((file) => file.path === "adapters/copilot/instructions.md")!.content).toContain("inspect skills with `/skills`");
  });

  it("emits model-neutral agents and deterministic drift checks", async () => {
    const manifest = await loadManifest(root);
    const files = await renderArtifacts(root, manifest, { installProfile: "full", commands: true });
    const codexCoder = files.find((file) => file.path.endsWith("codex/agents/coder.toml"))!.content;
    expect(parseToml(codexCoder)).not.toHaveProperty("model");
    expect(codexCoder).not.toContain("\\r\\n");
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
  }, 60_000);

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
