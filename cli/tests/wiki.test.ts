import { execFile as execFileCallback } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";
import { auditWiki, initWiki, inventoryRepository, reinitWiki } from "../src/wiki.js";

const execFile = promisify(execFileCallback);
const cliRoot = path.resolve(import.meta.dirname, "..");

type Shape = keyof typeof shapes;
const shapes = {
  "small-ts": {
    "package.json": JSON.stringify({ name: "small-ts", packageManager: "pnpm@9.0.0", scripts: { test: "vitest run", build: "tsc" } }),
    "pnpm-lock.yaml": "lockfileVersion: '9.0'\n",
    "src/index.ts": "export const answer = 42;\n",
    "tests/index.test.ts": "// test\n",
    "examples/demo/package.json": JSON.stringify({ name: "demo" }),
  },
  "small-python": {
    "pyproject.toml": "[build-system]\nrequires = ['setuptools']\n[tool.pytest.ini_options]\ntestpaths = ['tests']\n",
    "service/app.py": "def main(): return 'ok'\n",
    "tests/test_app.py": "def test_app(): assert True\n",
  },
  "medium-fe-be": {
    "package.json": JSON.stringify({ name: "root", packageManager: "yarn@4.0.0", scripts: { test: "yarn workspaces foreach test" } }),
    "apps/web/package.json": JSON.stringify({ name: "web", scripts: { build: "vite build", test: "vitest" }, dependencies: { react: "1" } }),
    "apps/web/src/index.tsx": "// frontend\n",
    "apps/api/package.json": JSON.stringify({ name: "api", scripts: { test: "vitest" }, dependencies: { express: "1" } }),
    "apps/api/server.ts": "// backend api\n",
    "apps/api/tests/server.test.ts": "// test\n",
  },
  "mixed-monorepo": {
    "package.json": JSON.stringify({ name: "mixed" }),
    "apps/web/package.json": JSON.stringify({ name: "web", scripts: { build: "vite build" } }),
    "apps/web/src/index.tsx": "// web\n",
    "services/api/pyproject.toml": "[build-system]\nrequires=['setuptools']\n",
    "services/api/app.py": "# api\n",
    "tools/worker/go.mod": "module worker\n",
    "tools/worker/main.go": "package main\nfunc main() {}\n",
  },
  desktop: {
    "package.json": JSON.stringify({ name: "desktop", scripts: { build: "electron-builder" }, dependencies: { electron: "1" } }),
    "src/electron.ts": "// desktop entry\n",
  },
  "ai-app": {
    "package.json": JSON.stringify({ name: "ai-app", scripts: { test: "vitest" }, dependencies: { openai: "1" } }),
    "src/openai-client.ts": "// ai provider\n",
    "evals/prompt.test.ts": "// eval\n",
  },
  "complex-ci-simple-source": {
    "package.json": JSON.stringify({ name: "ci-app", scripts: { test: "vitest", lint: "eslint ." } }),
    "yarn.lock": "# yarn lockfile\n",
    "src/index.ts": "export {};\n",
    ".github/workflows/ci.yml": "jobs:\n  test:\n    steps:\n      - run: npm run test\n      - run: npm run lint\n",
  },
  "generated-vendor-heavy": {
    "package.json": JSON.stringify({ name: "lean", scripts: { test: "vitest" } }),
    "src/index.ts": "export {};\n",
    "dist/generated.js": "generated\n",
    "vendor/library.js": "vendored\n",
    "coverage/report.js": "coverage\n",
  },
  "existing-curated-wiki": {
    "package.json": JSON.stringify({ name: "curated" }),
    "src/index.ts": "export {};\n",
    ".wiki/index.md": "# Human Wiki\n\nKeep this.\n",
    ".wiki/repository-map.md": "# Human Map\n",
    ".wiki/engineering.md": "# Human Engineering\n",
  },
  "legacy-kit": {
    "package.json": JSON.stringify({ name: "legacy" }),
    "src/index.ts": "export {};\n",
    ".kit/context/memory.md": "legacy memory\n",
    ".kit/workflows/build.md": "legacy workflow\n",
  },
  "nested-workspaces": {
    "package.json": JSON.stringify({ name: "root", packageManager: "pnpm@9.0.0", workspaces: ["packages/*"] }),
    "pnpm-lock.yaml": "lockfileVersion: '9.0'\n",
    "packages/a/package.json": JSON.stringify({ name: "a", scripts: { test: "vitest" } }),
    "packages/a/src/index.ts": "export {};\n",
    "packages/b/package.json": JSON.stringify({ name: "b", scripts: { build: "tsc" } }),
    "packages/b/src/index.ts": "export {};\n",
  },
} as const;

describe("wiki repository fixtures", () => {
  it("profiles all 11 compact repository shapes structurally", async () => {
    expect(Object.keys(shapes)).toHaveLength(11);
    for (const shape of Object.keys(shapes) as Shape[]) {
      const repo = await createFixture(shape);
      const profile = await inventoryRepository(repo);
      expect(profile.meaningfulFiles.length).toBeGreaterThan(0);
      expect(profile.trackedFiles.every((file) => !/node_modules/.test(file))).toBe(true);
      if (shape === "medium-fe-be" || shape === "mixed-monorepo" || shape === "nested-workspaces") {
        expect(profile.size).toBe("medium");
        expect(profile.workspaces.length).toBeGreaterThan(1);
      }
      if (shape === "generated-vendor-heavy") expect(profile.meaningfulFiles).toEqual(expect.not.arrayContaining(["dist/generated.js", "vendor/library.js", "coverage/report.js"]));
      if (shape === "legacy-kit") expect(profile.meaningfulFiles.some((file) => file.startsWith(".kit/"))).toBe(false);
      if (shape === "small-ts") {
        expect(profile.packageManager).toBe("pnpm");
        expect(profile.commands.some((command) => command.command === "pnpm run test")).toBe(true);
        expect(profile.workspaces.some((workspace) => workspace.path === "examples/demo")).toBe(false);
      }
      if (shape === "complex-ci-simple-source") {
        expect(profile.packageManager).toBe("yarn");
        expect(profile.commands.some((command) => command.command === "yarn run test")).toBe(true);
      }
      if (shape === "mixed-monorepo") {
        expect(profile.commands.some((command) => command.command === "npm --prefix apps/web run build" && command.cwd === "apps/web")).toBe(true);
        expect(profile.commands.some((command) => command.command === "npm run build")).toBe(false);
      }
      if (shape === "nested-workspaces") expect(profile.commands.some((command) => command.command === "pnpm --dir packages/a run test" && command.cwd === "packages/a")).toBe(true);
    }
  }, 30_000);

  it("initializes required pages and only evidence-justified optional pages", async () => {
    const small = await createFixture("small-ts");
    const result = await initWiki({ repo: small, wikiSplit: "auto", dryRun: false });
    expect(result.files).toEqual(expect.arrayContaining([".wiki/index.md", ".wiki/repository-map.md", ".wiki/architecture.md", ".wiki/engineering.md", ".wiki/testing.md"]));
    expect(result.files).not.toEqual(expect.arrayContaining([".wiki/frontend.md", ".wiki/backend.md", ".wiki/ai-ml.md", ".wiki/desktop.md"]));
    for (const page of result.files) expect((await readFile(path.join(small, page), "utf8")).split("\n").length).toBeLessThanOrEqual(page.endsWith("index.md") ? 100 : 220);

    const medium = await createFixture("medium-fe-be");
    const mediumResult = await initWiki({ repo: medium, wikiSplit: "auto", dryRun: false });
    expect(mediumResult.files).toEqual(expect.arrayContaining([".wiki/architecture.md", ".wiki/frontend.md", ".wiki/backend.md", ".wiki/workspaces/web.md", ".wiki/workspaces/api.md"]));
    expect(mediumResult.files).not.toContain(".wiki/ai-ml.md");
    const frontend = await readFile(path.join(medium, ".wiki/frontend.md"), "utf8");
    const backend = await readFile(path.join(medium, ".wiki/backend.md"), "utf8");
    expect(frontend).not.toContain("apps/api");
    expect(backend).not.toContain("apps/web");
    expect(`${frontend}\n${backend}`).not.toMatch(/This page routes|Inspect the listed current source/);
    expect(frontend).toContain("yarn --cwd apps/web run build");
    expect(frontend).not.toContain("yarn run build");
    expect(await readFile(path.join(medium, ".wiki/workspaces/web.md"), "utf8")).toContain("yarn --cwd apps/web run build");
    const ai = await createFixture("ai-app");
    expect((await initWiki({ repo: ai, wikiSplit: "root", dryRun: false })).files).toContain(".wiki/ai-ml.md");
    const desktop = await createFixture("desktop");
    expect((await initWiki({ repo: desktop, wikiSplit: "root", dryRun: false })).files).toContain(".wiki/desktop.md");
  }, 30_000);

  it("uses root workspace pages for auto and nested wikis only when explicit", async () => {
    const autoRepo = await createFixture("nested-workspaces");
    const auto = await initWiki({ repo: autoRepo, wikiSplit: "auto", dryRun: false });
    expect(auto.files).toContain(".wiki/workspaces/a.md");
    expect(auto.files.some((file) => file.startsWith("packages/a/.wiki/"))).toBe(false);
    const rootRepo = await createFixture("nested-workspaces");
    expect((await initWiki({ repo: rootRepo, wikiSplit: "root", dryRun: false })).files.some((file) => file.includes("workspaces/"))).toBe(false);
    const nestedRepo = await createFixture("nested-workspaces");
    const nested = await initWiki({ repo: nestedRepo, wikiSplit: "nested", dryRun: false });
    expect(nested.files).toEqual(expect.arrayContaining(["packages/a/.wiki/index.md", "packages/a/.wiki/repository-map.md", "packages/a/.wiki/engineering.md"]));
  }, 30_000);

  it("honors explicit workspace negations instead of re-including excluded manifests", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "root", packageManager: "pnpm@9.0.0", workspaces: ["packages/*", "!packages/excluded"] }),
      "pnpm-lock.yaml": "lockfileVersion: '9.0'\n",
      "packages/included/package.json": JSON.stringify({ name: "included", scripts: { test: "vitest" } }),
      "packages/included/src/index.ts": "export {};\n",
      "packages/excluded/package.json": JSON.stringify({ name: "excluded" }),
      "packages/excluded/src/index.ts": "export {};\n",
    }, "kit-wiki-negated-workspace-");

    const profile = await inventoryRepository(repo);
    expect(profile.workspaces.map((workspace) => workspace.path)).toContain("packages/included");
    expect(profile.workspaces.map((workspace) => workspace.path)).not.toContain("packages/excluded");
  });

  it("supports multi-level and brace workspace globs with nested negation precedence", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "root", workspaces: ["packages/{group,other}/**", "!packages/**/excluded"] }),
      "packages/group/included/package.json": JSON.stringify({ name: "included", scripts: { test: "vitest" } }),
      "packages/group/included/src/index.ts": "export {};\n",
      "packages/group/excluded/package.json": JSON.stringify({ name: "excluded", scripts: { build: "tsc", test: "vitest" } }),
      "packages/group/excluded/src/index.ts": "export {};\n",
      "packages/other/tool/package.json": JSON.stringify({ name: "tool", scripts: { build: "tsc" } }),
      "packages/other/tool/src/index.ts": "export {};\n",
    }, "kit-wiki-deep-globs-");

    const paths = (await inventoryRepository(repo)).workspaces.map((workspace) => workspace.path);
    expect(paths).toEqual(expect.arrayContaining(["packages/group/included", "packages/other/tool"]));
    expect(paths).not.toContain("packages/group/excluded");
  });

  it("refuses to invent package-manager commands when lockfiles conflict", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "ambiguous", scripts: { test: "vitest" } }),
      "pnpm-lock.yaml": "lockfileVersion: '9.0'\n",
      "yarn.lock": "# yarn lockfile\n",
      "src/index.ts": "export {};\n",
    }, "kit-wiki-ambiguous-manager-");

    await expect(inventoryRepository(repo)).rejects.toThrow(/ambiguous|multiple|conflicting.*lock/i);
  });

  it("is idempotent, preserves curated human content, and creates no forbidden durable surfaces", async () => {
    const repo = await createFixture("legacy-kit");
    await initWiki({ repo, wikiSplit: "auto", dryRun: false });
    const before = await readFile(path.join(repo, ".wiki/index.md"), "utf8");
    await initWiki({ repo, wikiSplit: "auto", dryRun: false });
    expect(await readFile(path.join(repo, ".wiki/index.md"), "utf8")).toBe(before);
    const paths = (await readdir(repo, { recursive: true, withFileTypes: true })).filter((entry) => entry.isFile()).map((entry) => path.relative(repo, path.join(entry.parentPath, entry.name)).replaceAll("\\", "/"));
    expect(paths.filter((file) => /\.wiki\/(\.features|.*memory|.*handoff|.*reflection|.*session-state|.*task-history)/i.test(file))).toEqual([]);

    const curated = await createFixture("existing-curated-wiki");
    await expect(initWiki({ repo: curated, wikiSplit: "root", dryRun: false })).rejects.toThrow(/human|conflict|overwrite/i);
    expect(await readFile(path.join(curated, ".wiki/index.md"), "utf8")).toContain("Keep this");
  });

  it("does not trust a tampered inventory to overwrite an unmarked human wiki page", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "human-wiki" }),
      "src/index.ts": "export {};\n",
      ".wiki/index.md": "# Human Wiki\n\nKeep this content.\n",
    }, "kit-wiki-tampered-inventory-");
    const human = await readFile(path.join(repo, ".wiki/index.md"), "utf8");
    const inventoryPath = path.join(repo, ".git/agentic-kit/wiki-generated.json");
    await mkdir(path.dirname(inventoryPath), { recursive: true });
    await writeFile(inventoryPath, `${JSON.stringify({
      schemaVersion: 1,
      files: [{ path: ".wiki/index.md", sha256: createHash("sha256").update(human, "utf8").digest("hex") }],
    }, null, 2)}\n`, "utf8");

    await expect(initWiki({ repo, wikiSplit: "root", dryRun: false })).rejects.toThrow(/human|unmarked|conflict|ownership/i);
    expect(await readFile(path.join(repo, ".wiki/index.md"), "utf8")).toBe(human);
  });

  it("reinitializes managed sections while preserving appended human guidance", async () => {
    const repo = await createFixture("small-ts");
    await initWiki({ repo, wikiSplit: "root", dryRun: false });
    const target = path.join(repo, ".wiki/engineering.md");
    await writeFile(target, `${await readFile(target, "utf8")}\n## Human notes\n\nKeep this repository-specific review note.\n`, "utf8");
    expect((await reinitWiki({ repo, wikiSplit: "root", dryRun: false })).status).toBe("WIKI REINITIALIZED");
    expect(await readFile(target, "utf8")).toContain("Keep this repository-specific review note.");
  });

  it("persists reviewed architect synthesis with exact source and symbol evidence", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "architect-app", scripts: { test: "vitest" } }),
      "src/main.ts": "export function bootstrap() { return createApiClient(); }\nfunction createApiClient() { return 'api'; }\n",
      "src/api/client.ts": "export function requestApi() { return '/v1'; }\n",
      "src/auth/session.ts": "export function requireSession() { return true; }\n",
      "src/ipc/bridge.ts": "export function invokeNative() { return 'ok'; }\n",
    }, "kit-wiki-synthesis-");
    const synthesisPath = ".git/agentic-kit/architect-synthesis.json";
    const synthesis = {
      schemaVersion: 1,
      pages: [
        { page: "architecture.md", sections: [{ heading: "Runtime control flow", body: "Application startup constructs the API boundary before serving repository behavior.", evidence: [{ path: "src/main.ts", symbols: ["bootstrap", "createApiClient"] }] }] },
        { page: "engineering.md", sections: [{ heading: "Code composition convention", body: "Repository modules expose named functions at explicit boundary files for callers to reuse.", evidence: [{ path: "src/api/client.ts", symbols: ["requestApi"] }] }] },
        { page: "api.md", sections: [{ heading: "Existing API access", body: "Outbound API work uses the existing request helper rather than introducing another client.", evidence: [{ path: "src/api/client.ts", symbols: ["requestApi"] }] }] },
        { page: "auth-security.md", sections: [{ heading: "Session boundary", body: "Protected behavior is expected to cross the established session guard boundary.", evidence: [{ path: "src/auth/session.ts", symbols: ["requireSession"] }] }] },
        { page: "ipc.md", sections: [{ heading: "Native invocation boundary", body: "Renderer-to-native requests pass through the tracked IPC bridge helper.", evidence: [{ path: "src/ipc/bridge.ts", symbols: ["invokeNative"] }] }] },
      ],
    };
    await mkdir(path.dirname(path.join(repo, synthesisPath)), { recursive: true });
    await writeFile(path.join(repo, synthesisPath), `${JSON.stringify(synthesis, null, 2)}\n`, "utf8");
    const result = await initWiki({ repo, wikiSplit: "root", dryRun: false, synthesis: synthesisPath });
    expect(result.files).toEqual(expect.arrayContaining([".wiki/architecture.md", ".wiki/engineering.md", ".wiki/api.md", ".wiki/auth-security.md", ".wiki/ipc.md"]));
    expect(await readFile(path.join(repo, ".wiki/architecture.md"), "utf8")).toContain("`src/main.ts#bootstrap`");
    expect(await readFile(path.join(repo, ".wiki/engineering.md"), "utf8")).toContain("Code composition convention");
    expect(await readFile(path.join(repo, ".wiki/api.md"), "utf8")).toContain("Existing API access");
    expect(await readFile(path.join(repo, ".wiki/auth-security.md"), "utf8")).toContain("Session boundary");
    expect(await readFile(path.join(repo, ".wiki/ipc.md"), "utf8")).toContain("Native invocation boundary");
    expect((await auditWiki({ repo })).findings).not.toContainEqual(expect.objectContaining({ code: "MISSING_PATH", detail: expect.stringContaining("#") }));

    synthesis.pages[0]!.sections[0]!.evidence[0]!.symbols = ["missingSymbol"];
    await writeFile(path.join(repo, synthesisPath), `${JSON.stringify(synthesis, null, 2)}\n`, "utf8");
    await expect(reinitWiki({ repo, wikiSplit: "root", dryRun: false, synthesis: synthesisPath })).rejects.toThrow(/symbol not found/i);
  });

  it("removes only unchanged stale managed pages and reports modified conflicts", async () => {
    const removedRepo = await createRepository({ "package.json": "{\"name\":\"ipc\"}", "src/ipc/bridge.ts": "export const bridge = true;\n" }, "kit-wiki-stale-remove-");
    await initWiki({ repo: removedRepo, wikiSplit: "root", dryRun: false });
    expect(await readFile(path.join(removedRepo, ".wiki/ipc.md"), "utf8")).toContain("src/ipc/bridge.ts");
    await rm(path.join(removedRepo, "src/ipc/bridge.ts"));
    await execFile("git", ["rm", "--cached", "src/ipc/bridge.ts"], { cwd: removedRepo });
    const removed = await reinitWiki({ repo: removedRepo, wikiSplit: "root", dryRun: false });
    expect(removed.findings).toContainEqual(expect.objectContaining({ code: "STALE_PAGE_REMOVED", page: "ipc.md" }));
    await expect(readFile(path.join(removedRepo, ".wiki/ipc.md"), "utf8")).rejects.toThrow();

    const retainedRepo = await createRepository({ "package.json": "{\"name\":\"ipc\"}", "src/ipc/bridge.ts": "export const bridge = true;\n" }, "kit-wiki-stale-retain-");
    await initWiki({ repo: retainedRepo, wikiSplit: "root", dryRun: false });
    const ipcPath = path.join(retainedRepo, ".wiki/ipc.md");
    await writeFile(ipcPath, `${await readFile(ipcPath, "utf8")}\nHuman IPC guidance.\n`, "utf8");
    await rm(path.join(retainedRepo, "src/ipc/bridge.ts"));
    await execFile("git", ["rm", "--cached", "src/ipc/bridge.ts"], { cwd: retainedRepo });
    const retained = await reinitWiki({ repo: retainedRepo, wikiSplit: "root", dryRun: false });
    expect(retained.findings).toContainEqual(expect.objectContaining({ code: "STALE_PAGE_CONFLICT", page: "ipc.md" }));
    expect(await readFile(ipcPath, "utf8")).toContain("Human IPC guidance");
  });

  it("reports malformed encoded local links without crashing the audit", async () => {
    const repo = await createFixture("small-ts");
    await initWiki({ repo, wikiSplit: "root", dryRun: false });
    const indexPath = path.join(repo, ".wiki/index.md");
    await writeFile(indexPath, `${await readFile(indexPath, "utf8")}\n[Malformed](%ZZ)\n`, "utf8");

    const audit = await auditWiki({ repo });
    expect(audit.findings).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "BROKEN_LINK", page: "index.md", detail: "%ZZ" }),
    ]));
  });

  it("reports missing required pages without writing during audit", async () => {
    for (const required of ["index.md", "repository-map.md", "architecture.md", "engineering.md"]) {
      const repo = await createFixture("small-ts");
      await initWiki({ repo, wikiSplit: "root", dryRun: false });
      await rm(path.join(repo, ".wiki", required));
      const audit = await auditWiki({ repo });
      expect(audit.findings).toEqual(expect.arrayContaining([expect.objectContaining({ code: "MISSING_REQUIRED_PAGE", page: required })]));
      await expect(readFile(path.join(repo, ".wiki", required), "utf8")).rejects.toThrow();
    }
  });

  it("audits source drift without modifying the wiki", async () => {
    const repo = await createFixture("small-ts");
    await initWiki({ repo, wikiSplit: "root", dryRun: false });
    await rm(path.join(repo, "src/index.ts"));
    await execFile("git", ["rm", "--cached", "src/index.ts"], { cwd: repo });
    const audit = await auditWiki({ repo });
    expect(audit.findings?.some((finding) => finding.code === "MISSING_PATH" && finding.detail === "src/index.ts")).toBe(true);
    const before = await readFile(path.join(repo, ".wiki/repository-map.md"), "utf8");
    await auditWiki({ repo });
    expect(await readFile(path.join(repo, ".wiki/repository-map.md"), "utf8")).toBe(before);
  });

  it("supports CLI dry-run with explicit paths containing spaces and non-ASCII", async () => {
    const repo = await createFixture("small-ts", "kit wiki Ω space ");
    const { stdout } = await execFile(process.execPath, ["--import", "tsx", path.join(cliRoot, "src/index.ts"), "wiki", "init", "--repo", repo, "--wiki-split", "auto", "--dry-run", "--yes"], { cwd: cliRoot, encoding: "utf8" });
    expect(stdout).toContain("DRY RUN");
    await expect(readFile(path.join(repo, ".wiki/index.md"), "utf8")).rejects.toThrow();
  });
});

async function createFixture(shape: Shape, prefix = `kit-wiki-${shape}-`): Promise<string> {
  return createRepository(shapes[shape], prefix);
}

async function createRepository(files: Record<string, string>, prefix: string): Promise<string> {
  const repo = await mkdtemp(path.join(tmpdir(), prefix));
  for (const [relativePath, content] of Object.entries(files)) {
    const target = path.join(repo, relativePath);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, content, "utf8");
  }
  await execFile("git", ["init", "--quiet"], { cwd: repo });
  await execFile("git", ["add", "."], { cwd: repo });
  return repo;
}
