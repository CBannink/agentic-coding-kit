import { execFile as execFileCallback } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";
import { auditWiki, initWiki as writeWiki, inventoryRepository, reinitWiki as rewriteWiki } from "../src/wiki.js";

const execFile = promisify(execFileCallback);
const cliRoot = path.resolve(import.meta.dirname, "..");
type WikiWriteOptions = Parameters<typeof writeWiki>[0];

async function initWiki(options: WikiWriteOptions) {
  return writeWiki(await withCompleteSynthesis(options));
}

async function reinitWiki(options: WikiWriteOptions) {
  return rewriteWiki(await withCompleteSynthesis(options));
}

async function withCompleteSynthesis(options: WikiWriteOptions): Promise<WikiWriteOptions> {
  const synthesisPath = options.synthesis ?? ".git/agentic-kit/test-reviewed-synthesis.json";
  const absolute = path.join(options.repo, synthesisPath);
  let synthesis: { schemaVersion: 1 | 2; pages: Array<Record<string, unknown>> } = { schemaVersion: 2, pages: [] };
  if (options.synthesis) synthesis = JSON.parse(await readFile(absolute, "utf8")) as typeof synthesis;
  const profile = await inventoryRepository(options.repo);
  const roots = [".wiki"];
  if (options.wikiSplit === "nested" && profile.workspaces.length > 1) roots.push(...profile.workspaces.map((workspace) => `${workspace.path}/.wiki`));
  const evidencePath = profile.manifests[0]!;
  const standardPages = ["repository-map.md", "engineering.md", "coding.md", "reviewing.md", "testing.md", "security.md"];
  const outputPath = (page: string): string => page.startsWith(".wiki/") || page.includes("/.wiki/") ? page : `.wiki/${page}`;
  const existing = new Set(synthesis.pages.map((page) => outputPath(String(page.page))));
  for (const root of roots) {
    for (const page of standardPages) {
      const fullPage = `${root}/${page}`;
      if (existing.has(fullPage)) continue;
      const id = `reviewed-${page.replace(".md", "")}`;
      const section = synthesis.schemaVersion === 2
        ? { id, heading: `Reviewed ${page.replace(".md", "")}`, useWhen: [page.replace(".md", "")], claimType: "fact", body: `The reviewed ${fullPage} guidance is grounded in the cited current manifest and remains subordinate to live source.`, evidence: [{ path: evidencePath }] }
        : { heading: `Reviewed ${page.replace(".md", "")}`, body: `The reviewed ${fullPage} guidance is grounded in the cited current manifest and remains subordinate to live source.`, evidence: [{ path: evidencePath }] };
      synthesis.pages.push(synthesis.schemaVersion === 2
        ? { page: fullPage, summary: `Reviewed ${page.replace(".md", "-")} guidance.`, useWhen: [page.replace(".md", "")], sections: [section] }
        : { page: fullPage, sections: [section] });
    }
  }
  await mkdir(path.dirname(absolute), { recursive: true });
  await writeFile(absolute, `${JSON.stringify(synthesis, null, 2)}\n`, "utf8");
  return { ...options, synthesis: synthesisPath };
}

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
      if (shape === "generated-vendor-heavy") {
        expect(profile.meaningfulFiles).toEqual(expect.not.arrayContaining(["dist/generated.js", "vendor/library.js", "coverage/report.js"]));
        expect(profile.excludedRoots).toEqual(["coverage", "dist", "vendor"]);
      }
      if (shape === "legacy-kit") {
        expect(profile.meaningfulFiles.some((file) => file.startsWith(".kit/"))).toBe(false);
        expect(profile.excludedRoots).toEqual([".kit"]);
      }
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

  it("requires reviewed synthesis for writes while retaining no-synthesis preview", async () => {
    const repo = await createFixture("small-ts");

    await expect(writeWiki({ repo, wikiSplit: "root", dryRun: false })).rejects.toThrow(/requires reviewed --synthesis/i);
    await expect(rewriteWiki({ repo, wikiSplit: "root", dryRun: false })).rejects.toThrow(/requires reviewed --synthesis/i);
    expect((await writeWiki({ repo, wikiSplit: "root", dryRun: true })).status).toBe("DRY RUN");
    await expect(readFile(path.join(repo, ".wiki/index.md"), "utf8")).rejects.toThrow();

    const result = await initWiki({ repo, wikiSplit: "root", dryRun: false });
    expect(result.status).toBe("WIKI INITIALIZED");
    expect((await auditWiki({ repo })).findings).toEqual([]);
  });

  it("initializes required pages and only evidence-justified optional pages", async () => {
    const small = await createFixture("small-ts");
    const result = await initWiki({ repo: small, wikiSplit: "auto", dryRun: false });
    const required = ["index.md", "repository-map.md", "engineering.md", "coding.md", "reviewing.md", "testing.md", "security.md"];
    expect(result.files.filter((file) => /^\.wiki\/[^/]+\.md$/.test(file))).toEqual(required.map((page) => `.wiki/${page}`).sort());
    expect(result.files).not.toContain(".wiki/architecture.md");
    expect(result.files).not.toEqual(expect.arrayContaining([".wiki/frontend.md", ".wiki/backend.md", ".wiki/ai-ml.md", ".wiki/desktop.md"]));
    for (const page of result.files) expect((await readFile(path.join(small, page), "utf8")).split("\n").length).toBeLessThanOrEqual(page.endsWith("index.md") ? 100 : 220);

    const medium = await createFixture("medium-fe-be");
    const mediumResult = await initWiki({ repo: medium, wikiSplit: "auto", dryRun: false });
    expect(mediumResult.files).toEqual(expect.arrayContaining([".wiki/engineering.md", ".wiki/coding.md", ".wiki/reviewing.md", ".wiki/security.md", ".wiki/frontend.md", ".wiki/backend.md", ".wiki/workspaces/web.md", ".wiki/workspaces/api.md"]));
    expect(mediumResult.files).not.toContain(".wiki/architecture.md");
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
    for (const workspace of ["a", "b"]) {
      expect(nested.files).toEqual(expect.arrayContaining(["index.md", "repository-map.md", "engineering.md", "coding.md", "reviewing.md", "testing.md", "security.md"].map((page) => `packages/${workspace}/.wiki/${page}`)));
    }
    await rm(path.join(nestedRepo, "packages/a/.wiki/security.md"));
    expect((await auditWiki({ repo: nestedRepo })).findings).toContainEqual(expect.objectContaining({ code: "MISSING_REQUIRED_PAGE", page: "packages/a/.wiki/security.md" }));
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
  }, 60_000);

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

  it("rejects a preserved human suffix when the complete reinitialized page exceeds its ceiling", async () => {
    const repo = await createFixture("small-ts");
    await initWiki({ repo, wikiSplit: "root", dryRun: false });
    const target = path.join(repo, ".wiki/engineering.md");
    const oversized = `${await readFile(target, "utf8")}\n## Human notes\n\n${"curated ".repeat(500)}\n`;
    await writeFile(target, oversized, "utf8");

    await expect(reinitWiki({ repo, wikiSplit: "root", dryRun: false })).rejects.toThrow(/engineering\.md.*500-word|500-word.*engineering\.md/i);
    expect(await readFile(target, "utf8")).toBe(oversized);
  });

  it("persists reviewed architect synthesis with exact source and symbol evidence", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "architect-app", scripts: { test: "vitest" } }),
      "src/main.ts": "export function bootstrap() { return createApiClient(); }\nfunction createApiClient() { return 'api'; }\n",
      "src/api/client.ts": "export function requestApi() { return '/v1'; }\n",
      "src/api/errors.ts": "export function formatApiError() { return 'error'; }\n",
      "src/auth/session.ts": "export function requireSession() { return true; }\n",
      "src/ipc/bridge.ts": "export function invokeNative() { return 'ok'; }\n",
    }, "kit-wiki-synthesis-");
    const synthesisPath = ".git/agentic-kit/architect-synthesis.json";
    const synthesis = {
      schemaVersion: 1,
      pages: [
        { page: "engineering.md", sections: [{ heading: "Runtime control flow", body: "Application startup constructs the API boundary before serving repository behavior.", evidence: [{ path: "src/main.ts", symbols: ["bootstrap", "createApiClient"] }] }] },
        { page: "coding.md", sections: [{ heading: "Code composition convention", body: "Repository modules expose named functions at explicit boundary files for callers to reuse.", evidence: [{ path: "src/api/client.ts", symbols: ["requestApi"] }, { path: "src/api/errors.ts", symbols: ["formatApiError"] }] }] },
        { page: "api.md", sections: [{ heading: "Existing API access", body: "Outbound API work uses the existing request helper rather than introducing another client.", evidence: [{ path: "src/api/client.ts", symbols: ["requestApi"] }] }] },
        { page: "auth-security.md", sections: [{ heading: "Session boundary", body: "Protected behavior is expected to cross the established session guard boundary.", evidence: [{ path: "src/auth/session.ts", symbols: ["requireSession"] }] }] },
        { page: "ipc.md", sections: [{ heading: "Native invocation boundary", body: "Renderer-to-native requests pass through the tracked IPC bridge helper.", evidence: [{ path: "src/ipc/bridge.ts", symbols: ["invokeNative"] }] }] },
      ],
    };
    await mkdir(path.dirname(path.join(repo, synthesisPath)), { recursive: true });
    await writeFile(path.join(repo, synthesisPath), `${JSON.stringify(synthesis, null, 2)}\n`, "utf8");
    const result = await initWiki({ repo, wikiSplit: "root", dryRun: false, synthesis: synthesisPath });
    expect(result.files).toEqual(expect.arrayContaining([".wiki/engineering.md", ".wiki/coding.md", ".wiki/api.md", ".wiki/auth-security.md", ".wiki/ipc.md"]));
    expect(result.files).not.toContain(".wiki/architecture.md");
    expect(await readFile(path.join(repo, ".wiki/engineering.md"), "utf8")).toContain("`src/main.ts#bootstrap`");
    expect(await readFile(path.join(repo, ".wiki/coding.md"), "utf8")).toContain("Code composition convention");
    expect(await readFile(path.join(repo, ".wiki/api.md"), "utf8")).toContain("Existing API access");
    expect(await readFile(path.join(repo, ".wiki/auth-security.md"), "utf8")).toContain("Session boundary");
    expect(await readFile(path.join(repo, ".wiki/ipc.md"), "utf8")).toContain("Native invocation boundary");
    expect((await auditWiki({ repo })).findings).not.toContainEqual(expect.objectContaining({ code: "MISSING_PATH", detail: expect.stringContaining("#") }));

    synthesis.pages[0]!.sections[0]!.evidence[0]!.symbols = ["missingSymbol"];
    await writeFile(path.join(repo, synthesisPath), `${JSON.stringify(synthesis, null, 2)}\n`, "utf8");
    await expect(reinitWiki({ repo, wikiSplit: "root", dryRun: false, synthesis: synthesisPath })).rejects.toThrow(/symbol not found/i);
  });

  it("routes schema-v2 coding patterns to exact sections and detects stale evidence", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "patterns", scripts: { test: "vitest" } }),
      "src/api/client.ts": "export function requestApi() { if (!ready()) return 'offline'; return '/v1'; }\nfunction ready() { return true; }\n",
      "src/api/errors.ts": "export function translateProviderError(value: unknown) { if (!value) return 'unknown'; return String(value); }\n",
      "tests/api.test.ts": "// behavior test\n",
    }, "kit-wiki-v2-");
    const synthesisPath = ".git/agentic-kit/architect-synthesis.json";
    const synthesis = {
      schemaVersion: 2,
      pages: [{
        page: "coding.md",
        summary: "Repository-specific implementation and verification patterns.",
        useWhen: ["implementation", "api client"],
        sections: [{
          id: "branching-and-errors",
          heading: "Branching and errors",
          useWhen: ["conditional logic", "provider error"],
          claimType: "convention",
          body: "Boundary helpers use guard clauses and translate provider failures before returning them to callers.",
          evidence: [
            { path: "src/api/client.ts", symbols: ["requestApi"] },
            { path: "src/api/errors.ts", symbols: ["translateProviderError"] },
          ],
        }],
      }],
    };
    await mkdir(path.dirname(path.join(repo, synthesisPath)), { recursive: true });
    await writeFile(path.join(repo, synthesisPath), `${JSON.stringify(synthesis, null, 2)}\n`, "utf8");
    await initWiki({ repo, wikiSplit: "root", dryRun: false, synthesis: synthesisPath });
    const index = await readFile(path.join(repo, ".wiki/index.md"), "utf8");
    expect(index).toContain("coding.md#branching-and-errors");
    expect(index).toContain(synthesis.pages[0]!.summary);
    expect(await readFile(path.join(repo, ".wiki/coding.md"), "utf8")).toContain('<a id="branching-and-errors"></a>');
    expect((await auditWiki({ repo })).findings).toEqual([]);

    await writeFile(path.join(repo, "package.json"), JSON.stringify({ name: "patterns-updated", scripts: { test: "vitest" } }), "utf8");
    await writeFile(path.join(repo, "src/api/errors.ts"), "export const replacement = 'changed';\n", "utf8");
    expect((await auditWiki({ repo })).findings).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "STALE_EVIDENCE", page: "engineering.md", detail: "package.json" }),
      expect.objectContaining({ code: "STALE_EVIDENCE", page: "coding.md", detail: "src/api/errors.ts" }),
      expect.objectContaining({ code: "MISSING_SYMBOL", page: "coding.md", detail: "src/api/errors.ts#translateProviderError" }),
    ]));
  });

  it("applies schema-v2 synthesis and complete audit invariants to an explicit nested wiki root", async () => {
    const repo = await createFixture("nested-workspaces");
    const synthesisPath = ".git/agentic-kit/architect-synthesis.json";
    const synthesis = {
      schemaVersion: 2,
      pages: [{
        page: "packages/a/.wiki/coding.md",
        summary: "Workspace-specific module export guidance.",
        useWhen: ["package a implementation"],
        sections: [{
          id: "module-exports",
          heading: "Module exports",
          useWhen: ["package a exports"],
          claimType: "fact",
          body: "The package entry module currently exposes its public surface through explicit exports.",
          evidence: [
            { path: "packages/a/src/index.ts", symbols: ["export"] },
            { path: "packages/a/package.json", symbols: ["name"] },
          ],
        }],
      }],
    };
    await mkdir(path.dirname(path.join(repo, synthesisPath)), { recursive: true });
    await writeFile(path.join(repo, synthesisPath), `${JSON.stringify(synthesis, null, 2)}\n`, "utf8");
    await initWiki({ repo, wikiSplit: "nested", dryRun: false, synthesis: synthesisPath });
    const nestedIndex = path.join(repo, "packages/a/.wiki/index.md");
    const nestedCoding = path.join(repo, "packages/a/.wiki/coding.md");
    expect(await readFile(nestedIndex, "utf8")).toContain("coding.md#module-exports");
    expect(await readFile(nestedIndex, "utf8")).toContain(synthesis.pages[0]!.summary);
    expect(await readFile(nestedCoding, "utf8")).toContain('<a id="module-exports"></a>');
    expect((await auditWiki({ repo })).findings).toEqual([]);

    await writeFile(nestedCoding, (await readFile(nestedCoding, "utf8"))
      .replace("agentic-coding-kit-wiki:generated", "local-wiki")
      .replace('id="module-exports"', 'id="changed-export"'), "utf8");
    await writeFile(nestedIndex, `${await readFile(nestedIndex, "utf8")}\n[Missing](missing.md)\n`, "utf8");
    await writeFile(path.join(repo, "packages/a/src/index.ts"), "export const changed = true;\n", "utf8");
    expect((await auditWiki({ repo })).findings).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "INVALID_OWNERSHIP", page: "packages/a/.wiki/coding.md" }),
      expect.objectContaining({ code: "MODIFIED_MANAGED_CONTENT", page: "packages/a/.wiki/coding.md" }),
      expect.objectContaining({ code: "BROKEN_ANCHOR", page: "packages/a/.wiki/index.md", detail: "coding.md#module-exports" }),
      expect.objectContaining({ code: "BROKEN_LINK", page: "packages/a/.wiki/index.md", detail: "missing.md" }),
      expect.objectContaining({ code: "STALE_EVIDENCE", page: "packages/a/.wiki/coding.md", detail: "packages/a/src/index.ts" }),
    ]));
  });

  it("rejects incidental convention claims without independent evidence", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "incidental" }),
      "src/package-helper.ts": "export function requestApi() { return '/v1'; }\n",
    }, "kit-wiki-convention-");
    const synthesisPath = ".git/agentic-kit/architect-synthesis.json";
    const synthesis = {
      schemaVersion: 2,
      pages: [{
        page: "coding.md",
        summary: "Repository-specific coding conventions.",
        useWhen: ["implementation"],
        sections: [{
          id: "api-style",
          heading: "API style",
          useWhen: ["api client"],
          claimType: "convention",
          body: "All outbound requests must use this exact local helper pattern.",
          evidence: [{ path: "src/package-helper.ts", symbols: ["requestApi"] }],
        }],
      }],
    };
    await mkdir(path.dirname(path.join(repo, synthesisPath)), { recursive: true });
    await writeFile(path.join(repo, synthesisPath), `${JSON.stringify(synthesis, null, 2)}\n`, "utf8");
    await expect(initWiki({ repo, wikiSplit: "root", dryRun: false, synthesis: synthesisPath })).rejects.toThrow(/authoritative source or two independent code paths/i);
  });

  it("enforces coding-practice provenance for legacy synthesis", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "legacy-practice" }),
      "src/client.ts": "export function requestApi() { return '/v1'; }\n",
    }, "kit-wiki-legacy-practice-");
    const synthesisPath = ".git/agentic-kit/architect-synthesis.json";
    const synthesis = {
      schemaVersion: 1,
      pages: [{
        page: "coding.md",
        sections: [{
          heading: "API helper practice",
          body: "Outbound requests use the repository helper so callers share one implementation path.",
          evidence: [{ path: "src/client.ts", symbols: ["requestApi"] }],
        }],
      }],
    };
    await mkdir(path.dirname(path.join(repo, synthesisPath)), { recursive: true });
    await writeFile(path.join(repo, synthesisPath), `${JSON.stringify(synthesis, null, 2)}\n`, "utf8");

    await expect(initWiki({ repo, wikiSplit: "root", dryRun: false, synthesis: synthesisPath })).rejects.toThrow(/authoritative source or two independent code paths/i);
  });

  it("previews, backs up, and replaces an explicitly adopted legacy wiki", async () => {
    const repo = await createRepository({
      "package.json": JSON.stringify({ name: "legacy-wiki", scripts: { test: "vitest" } }),
      "src/index.ts": "export const value = true;\n",
      ".wiki/index.md": "# Legacy Index\n\nOld architecture.\n",
      ".wiki/features.md": "# Legacy Features\n",
      ".wiki/.features": "legacy-machine-state\n",
    }, "kit-wiki-adopt-");

    await expect(reinitWiki({ repo, wikiSplit: "root", dryRun: false })).rejects.toThrow(/conflict/i);
    const preview = await reinitWiki({ repo, wikiSplit: "root", dryRun: true, adoptExisting: true });
    expect(preview.findings).toEqual(expect.arrayContaining([
      expect.objectContaining({ code: "LEGACY_PAGE_REPLACED", page: "index.md" }),
      expect.objectContaining({ code: "LEGACY_PAGE_DROPPED", page: "features.md" }),
    ]));
    expect(await readFile(path.join(repo, ".wiki/index.md"), "utf8")).toContain("Legacy Index");

    await reinitWiki({ repo, wikiSplit: "root", dryRun: false, adoptExisting: true, confirmed: true });
    expect(await readFile(path.join(repo, ".wiki/index.md"), "utf8")).toContain("agentic-coding-kit-wiki:generated");
    await expect(readFile(path.join(repo, ".wiki/features.md"), "utf8")).rejects.toThrow();
    await expect(readFile(path.join(repo, ".wiki/.features"), "utf8")).rejects.toThrow();
    const backupRoot = path.join(repo, ".git/agentic-kit/wiki-backups");
    const backups = (await readdir(backupRoot, { recursive: true, withFileTypes: true })).filter((entry) => entry.isFile()).map((entry) => entry.name);
    expect(backups).toEqual(expect.arrayContaining(["index.md", "features.md", ".features"]));
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
    for (const required of ["index.md", "repository-map.md", "engineering.md", "coding.md", "reviewing.md", "testing.md", "security.md"]) {
      const repo = await createFixture("small-ts");
      await initWiki({ repo, wikiSplit: "root", dryRun: false });
      await rm(path.join(repo, ".wiki", required));
      const audit = await auditWiki({ repo });
      expect(audit.findings).toEqual(expect.arrayContaining([expect.objectContaining({ code: "MISSING_REQUIRED_PAGE", page: required })]));
      await expect(readFile(path.join(repo, ".wiki", required), "utf8")).rejects.toThrow();
    }
  });

  it("audits the exact standard-page word ceilings without writing", async () => {
    const budgets: Record<string, number> = { "index.md": 250, "repository-map.md": 400, "engineering.md": 500, "coding.md": 400, "reviewing.md": 400, "testing.md": 400, "security.md": 400 };
    for (const [page, budget] of Object.entries(budgets)) {
      const repo = await createFixture("small-ts");
      await initWiki({ repo, wikiSplit: "root", dryRun: false });
      const target = path.join(repo, ".wiki", page);
      await writeFile(target, `${await readFile(target, "utf8")}\n${"overflow ".repeat(budget + 1)}`, "utf8");
      const before = await readFile(target, "utf8");
      expect((await auditWiki({ repo })).findings).toContainEqual(expect.objectContaining({ code: "OVERSIZED_PAGE", page, detail: expect.stringContaining(`exceeds ${budget}`) }));
      expect(await readFile(target, "utf8")).toBe(before);
    }
  }, 60_000);

  it("audits source drift without modifying the wiki", async () => {
    const repo = await createFixture("small-ts");
    await initWiki({ repo, wikiSplit: "root", dryRun: false });
    await rm(path.join(repo, "src/index.ts"));
    await execFile("git", ["rm", "--cached", "src/index.ts"], { cwd: repo });
    const audit = await auditWiki({ repo });
    expect(audit.findings?.some((finding) => finding.code === "MISSING_PATH" && finding.detail === "src/index.ts")).toBe(true);
    const mapPath = path.join(repo, ".wiki/repository-map.md");
    const tampered = (await readFile(mapPath, "utf8")).replace("# Repository Map", "# Locally Modified Map");
    await writeFile(mapPath, tampered, "utf8");
    expect((await auditWiki({ repo })).findings).toContainEqual(expect.objectContaining({
      code: "MODIFIED_MANAGED_CONTENT",
      page: "repository-map.md",
    }));
    expect(await readFile(mapPath, "utf8")).toBe(tampered);
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
