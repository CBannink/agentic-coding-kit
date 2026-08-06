import { execFile as execFileCallback } from "node:child_process";
import { createHash } from "node:crypto";
import type { Dirent } from "node:fs";
import { promisify } from "node:util";
import { lstat, readFile, readdir } from "node:fs/promises";
import path from "node:path";
import picomatch from "picomatch";
import { parseFrontmatter, parseToml, parseYaml, serializeFrontmatter } from "./parsers.js";
import { atomicWriteContained, resolveContainedPath, resolveExistingContainedPath, unlinkContained } from "./paths.js";
import { findBrokenLocalMarkdownLinks } from "./links.js";
import { collectPrHistory, type PrHistoryCache, type PrHistoryMode } from "./pr-history.js";

const execFile = promisify(execFileCallback);
const WIKI_MARKER = "<!-- agentic-coding-kit-wiki:generated -->";
const WIKI_SCHEMA_VERSION = 2;
const WIKI_INVENTORY = ".git/agentic-kit/wiki-generated.json";
const MANAGED_END = "<!-- agentic-coding-kit-wiki:managed-end -->";
const NOISE_SEGMENTS = new Set([".git", ".kit", ".wiki", ".agentic-kit-backup", "node_modules", "vendor", "dist", "build", "coverage", "cache", ".cache", "target"]);
const SOURCE_EXTENSIONS = new Set([".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".rs", ".java", ".kt", ".cs", ".swift", ".rb", ".php"]);
const REQUIRED_WIKI_PAGES = ["index.md", "repository-map.md", "engineering.md", "coding.md", "reviewing.md", "testing.md", "security.md"] as const;
const WIKI_WORD_BUDGETS: Readonly<Record<(typeof REQUIRED_WIKI_PAGES)[number], number>> = {
  "index.md": 250,
  "repository-map.md": 400,
  "engineering.md": 500,
  "coding.md": 400,
  "reviewing.md": 400,
  "testing.md": 400,
  "security.md": 400,
};

export type WikiSplit = "auto" | "root" | "nested";
export type RepositorySize = "small" | "medium" | "large";

export interface VerifiedCommand { purpose: string; command: string; source: string; cwd: string }
export interface WorkspaceProfile { name: string; path: string; manifest: string; commands: VerifiedCommand[] }
export interface AreaProfile { id: string; roots: string[]; sources: string[]; tests: string[]; commands: VerifiedCommand[] }
export interface RepositoryProfile {
  root: string;
  trackedFiles: string[];
  meaningfulFiles: string[];
  sourceFiles: string[];
  languages: string[];
  manifests: string[];
  lockfiles: string[];
  packageManager: "npm" | "pnpm" | "yarn";
  ciFiles: string[];
  testRoots: string[];
  entryPoints: string[];
  excludedRoots: string[];
  workspaces: WorkspaceProfile[];
  commands: VerifiedCommand[];
  size: RepositorySize;
  signals: Set<string>;
  areas: Record<string, AreaProfile>;
}

export interface WikiFile { path: string; content: string; sourcePaths: string[]; sourceEvidence?: WikiSynthesisEvidence[] }
export interface WikiInitOptions {
  repo: string;
  wikiSplit: WikiSplit;
  dryRun: boolean;
  synthesis?: string;
  prHistory?: PrHistoryMode;
  prHistoryConsented?: boolean;
  interactive?: boolean;
  adoptExisting?: boolean;
  confirmed?: boolean;
}
export interface WikiAuditOptions { repo: string }
export interface WikiResult { status: string; files: string[]; findings?: WikiFinding[]; profile?: RepositoryProfile }
export interface WikiFinding { code: string; page: string; detail: string; line?: number }

interface WikiInventoryEvidence { path: string; sha256: string; symbols: string[] }
interface WikiInventoryFile {
  path: string;
  sourceId: string;
  sha256: string;
  managedSha256?: string;
  evidence?: WikiInventoryEvidence[];
}
interface WikiInventory { schemaVersion: 1 | 2; sourceRevision?: string; files: WikiInventoryFile[] }
interface WikiSynthesisEvidence { path: string; symbols?: string[] }
interface WikiReviewEvidence { provider: "github" | "azure"; pullRequest: number; threadId: string }
type WikiClaimType = "fact" | "flow" | "convention" | "verification";
interface WikiSynthesisSection {
  id?: string;
  heading: string;
  useWhen?: string[];
  claimType?: WikiClaimType;
  body: string;
  evidence: WikiSynthesisEvidence[];
  reviewEvidence?: WikiReviewEvidence[];
}
interface WikiSynthesisPage {
  page: string;
  summary?: string;
  useWhen?: string[];
  sections: WikiSynthesisSection[];
}
interface WikiSynthesis { schemaVersion: 1 | 2; pages: WikiSynthesisPage[] }
interface ApplyWikiResult { findings: WikiFinding[] }

export async function inventoryRepository(repo: string): Promise<RepositoryProfile> {
  const root = path.resolve(repo);
  const { stdout } = await execFile("git", ["-C", root, "ls-files", "-z"], { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 });
  const indexedFiles = stdout.split("\0").filter(Boolean).map(normalize).sort();
  const trackedFiles = (await Promise.all(indexedFiles.map(async (file) => await fileExists(path.join(root, file)) ? file : undefined))).filter((file): file is string => Boolean(file));
  const excludedRoots = [...new Set(trackedFiles
    .map((file) => file.split("/", 1)[0]!)
    .filter((rootName) => NOISE_SEGMENTS.has(rootName)))].sort();
  const meaningfulFiles = trackedFiles.filter((file) => !file.split("/").some((segment) => NOISE_SEGMENTS.has(segment)) && !isBinaryNoise(file));
  const sourceFiles = meaningfulFiles.filter((file) => SOURCE_EXTENSIONS.has(path.posix.extname(file).toLowerCase()));
  const languages = [...new Set(sourceFiles.map(languageFor))].filter(Boolean).sort();
  const manifests = meaningfulFiles.filter(isManifest).sort();
  const lockfiles = meaningfulFiles.filter((file) => /(^|\/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock)$/.test(file)).sort();
  const ciFiles = meaningfulFiles.filter((file) => file.startsWith(".github/workflows/") || /(^|\/)(azure-pipelines|gitlab-ci|circleci|Jenkinsfile)/i.test(file)).sort();
  const testRoots = [...new Set(meaningfulFiles.filter(isTestFile).map(testRootFor))].sort();
  const entryPoints = meaningfulFiles.filter(isEntryPoint).slice(0, 40);
  const packageManager = await detectPackageManager(root, trackedFiles);
  const commands = await collectVerifiedCommands(root, manifests, ciFiles, packageManager);
  const workspaces = await detectWorkspaces(root, manifests, trackedFiles, packageManager);
  const size: RepositorySize = meaningfulFiles.length > 1500 || workspaces.length > 8 ? "large" : meaningfulFiles.length > 300 || workspaces.length > 1 ? "medium" : "small";
  const areas = deriveAreas(meaningfulFiles, testRoots, commands, workspaces);
  const signals = new Set<string>();
  for (const area of Object.values(areas)) if (isSubstantiveArea(area)) signals.add(area.id);
  if (testRoots.length) signals.add("testing");
  if (workspaces.length > 1 || size !== "small") signals.add("architecture");
  return { root, trackedFiles, meaningfulFiles, sourceFiles, languages, manifests, lockfiles, packageManager, ciFiles, testRoots, entryPoints, excludedRoots, workspaces, commands, size, signals, areas };
}

export async function initWiki(options: WikiInitOptions): Promise<WikiResult> {
  requireWriteSynthesis(options);
  const profile = await inventoryRepository(options.repo);
  const history = await collectPrHistory({ repo: profile.root, mode: options.prHistory ?? "off", consented: options.prHistoryConsented, interactive: options.interactive, dryRun: options.dryRun });
  const files = await renderWithSynthesis(profile, options.wikiSplit, options.synthesis, history.cache);
  validateWikiFiles(profile, files);
  const applied = await applyWikiFiles(profile, files, options.dryRun, "init");
  const findings = history.status === "COLLECTED" ? applied.findings : history.reason ? [...applied.findings, { code: "PR_HISTORY_SKIPPED", page: "review-practices.md", detail: history.reason }] : applied.findings;
  return { status: options.dryRun ? "DRY RUN" : "WIKI INITIALIZED", files: files.map((file) => file.path), findings, profile };
}

export async function reinitWiki(options: WikiInitOptions): Promise<WikiResult> {
  requireWriteSynthesis(options);
  const profile = await inventoryRepository(options.repo);
  const history = await collectPrHistory({ repo: profile.root, mode: options.prHistory ?? "off", consented: options.prHistoryConsented, interactive: options.interactive, dryRun: options.dryRun });
  const files = await renderWithSynthesis(profile, options.wikiSplit, options.synthesis, history.cache);
  validateWikiFiles(profile, files);
  const applied = await applyWikiFiles(profile, files, options.dryRun, "reinit", {
    adoptExisting: Boolean(options.adoptExisting),
    confirmed: Boolean(options.confirmed),
  });
  const findings = history.status === "COLLECTED" ? applied.findings : history.reason ? [...applied.findings, { code: "PR_HISTORY_SKIPPED", page: "review-practices.md", detail: history.reason }] : applied.findings;
  return { status: options.dryRun ? "DRY RUN" : "WIKI REINITIALIZED", files: files.map((file) => file.path), findings, profile };
}

async function renderWithSynthesis(profile: RepositoryProfile, split: WikiSplit, synthesisPath?: string, history?: PrHistoryCache): Promise<WikiFile[]> {
  const files = renderWiki(profile, split);
  if (!synthesisPath) return files;
  const inputPath = await resolveExistingContainedPath(profile.root, synthesisPath, "repository root");
  const synthesis = JSON.parse(await readFile(inputPath, "utf8")) as WikiSynthesis;
  await applyArchitectSynthesis(profile, files, synthesis, history);
  validateSynthesisCoverage(files, synthesis);
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

function requireWriteSynthesis(options: WikiInitOptions): void {
  if (!options.dryRun && !options.synthesis) {
    throw new Error("Wiki init/reinit write mode requires reviewed --synthesis from the agent-driven wiki flow; use --dry-run for inventory preview");
  }
}

function validateSynthesisCoverage(files: WikiFile[], synthesis: WikiSynthesis): void {
  const synthesized = new Set(synthesis.pages.map((page) => synthesisOutputPath(page.page, synthesis.schemaVersion)));
  const roots = new Set(files.map((file) => wikiRootFor(file.path)));
  const missing: string[] = [];
  for (const root of roots) {
    for (const page of REQUIRED_WIKI_PAGES) {
      if (page !== "index.md" && !synthesized.has(`${root}/${page}`)) missing.push(`${root}/${page}`);
    }
  }
  if (missing.length) throw new Error(`Reviewed synthesis must cover every standard content page:\n${missing.join("\n")}`);
}

async function applyArchitectSynthesis(profile: RepositoryProfile, files: WikiFile[], synthesis: WikiSynthesis, collectedHistory?: PrHistoryCache): Promise<void> {
  if (![1, 2].includes(synthesis?.schemaVersion) || !Array.isArray(synthesis.pages)) {
    throw new Error("Architect synthesis must use schemaVersion 1 or 2 and a pages array");
  }
  const tracked = new Set(profile.meaningfulFiles);
  const history = collectedHistory ?? await loadPrHistoryCache(profile.root);
  const seenPages = new Set<string>();
  const routeRowsByRoot = new Map<string, string[]>();
  for (const page of synthesis.pages) {
    if (!page || typeof page.page !== "string" || !Array.isArray(page.sections) || !page.sections.length) throw new Error("Each architect synthesis page needs a page and non-empty sections");
    if (synthesis.schemaVersion === 2) {
      if (typeof page.summary !== "string" || page.summary.trim().length < 12 || page.summary.length > 240) throw new Error(`Schema-v2 page ${page.page} needs a concise summary`);
      validateUseWhen(page.useWhen, `page ${page.page}`);
    }
    const outputPath = synthesisOutputPath(page.page, synthesis.schemaVersion);
    const wikiRoot = wikiRootFor(outputPath);
    const relativePage = normalize(path.posix.relative(wikiRoot, outputPath));
    if (seenPages.has(outputPath)) throw new Error(`Duplicate architect synthesis page: ${page.page}`);
    if (path.posix.basename(relativePage) === "architecture.md") throw new Error("Architecture synthesis belongs in engineering.md");
    if (path.posix.basename(relativePage) === "coding.md" && page.sections.length > 10) throw new Error("coding.md supports at most ten practice sections");
    seenPages.add(outputPath);
    if (path.posix.basename(relativePage) === "review-practices.md" && !history) throw new Error("Review practices require a collected PR-history cache from this wiki init/reinit");
    let file = files.find((candidate) => normalize(candidate.path) === outputPath);
    if (!file) {
      if (wikiRoot !== ".wiki" && !files.some((candidate) => wikiRootFor(candidate.path) === wikiRoot)) throw new Error(`Architect synthesis targets an ungenerated wiki root: ${wikiRoot}`);
      const body = `${wikiOwnershipHeader(outputPath)}\n# ${title(path.posix.basename(relativePage, ".md"))}\n\n${MANAGED_END}\n`;
      file = { path: outputPath, content: body, sourcePaths: [] };
      files.push(file);
    }
    const renderedSections: string[] = [];
    const sourceEvidence: WikiSynthesisEvidence[] = [];
    const sectionIds = new Set([...file.content.matchAll(/<a id="([a-z][a-z0-9-]+)"><\/a>/g)].map((match) => match[1]!));
    for (const section of page.sections) {
      if (!section || typeof section.heading !== "string" || !/^[A-Z0-9][^\r\n]{2,100}$/i.test(section.heading) || typeof section.body !== "string" || section.body.trim().length < 20 || section.body.length > 6000 || !Array.isArray(section.evidence) || !section.evidence.length) {
        throw new Error(`Invalid architect synthesis section in ${relativePage}`);
      }
      const sectionId = synthesis.schemaVersion === 2 ? section.id : slug(section.heading);
      if (!sectionId || !/^[a-z][a-z0-9-]{1,80}$/.test(sectionId)) throw new Error(`Invalid section id in ${relativePage}: ${sectionId ?? "missing"}`);
      if (sectionIds.has(sectionId)) throw new Error(`Duplicate section id in ${relativePage}: ${sectionId}`);
      sectionIds.add(sectionId);
      if (synthesis.schemaVersion === 2) {
        validateUseWhen(section.useWhen, `${relativePage}#${sectionId}`);
        if (!["fact", "flow", "convention", "verification"].includes(section.claimType ?? "")) throw new Error(`Invalid claimType in ${relativePage}#${sectionId}`);
      }
      const evidenceLabels: string[] = [];
      const independentEvidence = new Set<string>();
      let authoritativeConventionSource = false;
      for (const evidence of section.evidence) {
        const evidencePath = normalize(evidence.path);
        if (!tracked.has(evidencePath)) throw new Error(`Architect synthesis evidence is not tracked source: ${evidencePath}`);
        if (isGeneratedEvidencePath(evidencePath)) throw new Error(`Architect synthesis evidence must cite canonical source: ${evidencePath}`);
        const source = await readFile(path.join(profile.root, evidencePath), "utf8");
        const symbols = evidence.symbols ?? [];
        for (const symbol of symbols) {
          if (!symbol || symbol.length > 160 || !source.includes(symbol)) throw new Error(`Architect synthesis symbol not found in ${evidencePath}: ${symbol}`);
        }
        file.sourcePaths.push(evidencePath);
        sourceEvidence.push({ path: evidencePath, symbols });
        independentEvidence.add(evidencePath);
        authoritativeConventionSource ||= isAuthoritativeConventionSource(evidencePath);
        evidenceLabels.push(symbols.length ? symbols.map((symbol) => `\`${evidencePath}#${symbol}\``).join(", ") : `\`${evidencePath}\``);
      }
      if (path.posix.basename(relativePage) === "coding.md" && !authoritativeConventionSource && independentEvidence.size < 2) {
        throw new Error(`Coding practice ${relativePage}#${sectionId} needs an authoritative source or two independent code paths`);
      }
      const reviewEvidence = section.reviewEvidence ?? [];
      if (relativePage === "review-practices.md") {
        if (!reviewEvidence.length) throw new Error("Review-practice sections require historical review evidence");
        validateReviewLesson(reviewEvidence, history!);
        evidenceLabels.push(...reviewEvidence.map((evidence) => `${evidence.provider === "github" ? "GitHub" : "Azure"} PR #${evidence.pullRequest}, thread ${evidence.threadId}`));
      } else if (reviewEvidence.length) {
        throw new Error("Historical review evidence is allowed only in review-practices.md");
      }
      renderedSections.push(`<a id="${sectionId}"></a>\n## ${section.heading.trim()}\n\n${section.body.trim()}\n\nEvidence: ${evidenceLabels.join(", ")}`);
      const signals = synthesis.schemaVersion === 2 ? [...new Set([...(page.useWhen ?? []), ...(section.useWhen ?? [])])] : [path.posix.basename(relativePage, ".md").replaceAll("-", " ")];
      const summary = synthesis.schemaVersion === 2 ? page.summary!.trim().replace(/\s+/g, " ").replaceAll("|", "\\|") : section.heading.trim();
      const routeRows = routeRowsByRoot.get(wikiRoot) ?? [];
      routeRows.push(`| ${signals.join(", ")} | ${summary} | [${relativePage}#${sectionId}](${relativePage}#${sectionId}) |`);
      routeRowsByRoot.set(wikiRoot, routeRows);
    }
    const markerIndex = file.content.indexOf(MANAGED_END);
    if (markerIndex < 0) throw new Error(`Managed boundary missing from ${outputPath}`);
    file.content = `${file.content.slice(0, markerIndex).trimEnd()}\n\n${renderedSections.join("\n\n")}\n\n${file.content.slice(markerIndex)}`;
    file.sourcePaths = [...new Set(file.sourcePaths)];
    file.sourceEvidence = dedupeSynthesisEvidence([...(file.sourceEvidence ?? []), ...sourceEvidence]);
  }
  const practices = files.find((file) => normalize(file.path) === ".wiki/review-practices.md");
  if (practices && practices.content.length > 20_000) throw new Error("review-practices.md exceeds the 20,000-character knowledge budget");
  for (const [wikiRoot, routeRows] of routeRowsByRoot) {
    const index = files.find((file) => normalize(file.path) === `${wikiRoot}/index.md`);
    if (!index) throw new Error(`Generated wiki index is missing: ${wikiRoot}/index.md`);
    const routes = `## Reviewed routes\n\n| Task signals | Reviewed summary | Read |\n|---|---|---|\n${routeRows.join("\n")}`;
    const markerIndex = index.content.indexOf(MANAGED_END);
    if (markerIndex < 0) throw new Error(`Managed boundary missing from ${index.path}`);
    index.content = `${index.content.slice(0, markerIndex).trimEnd()}\n\n${routes}\n\n${index.content.slice(markerIndex)}`;
  }
}

function synthesisOutputPath(page: string, schemaVersion: 1 | 2): string {
  const normalized = normalize(page).replace(/^\.\//, "");
  const outputPath = normalized.startsWith(".wiki/")
    ? normalized
    : schemaVersion === 2 && normalized.includes("/.wiki/")
      ? normalized
      : `.wiki/${normalized}`;
  if (!/^(?:[a-zA-Z0-9._-]+\/)*\.wiki\/(?:[a-z][a-z0-9-]*\/)*[a-z][a-z0-9-]*\.md$/.test(outputPath)) {
    throw new Error(`Invalid architect synthesis page: ${page}`);
  }
  return outputPath;
}

function validateUseWhen(value: string[] | undefined, label: string): void {
  if (!Array.isArray(value) || !value.length || value.length > 12 || value.some((item) => typeof item !== "string" || !/^[a-z0-9][a-z0-9 /_.-]{1,60}$/i.test(item))) {
    throw new Error(`${label} needs one to twelve concise useWhen signals`);
  }
}

function isAuthoritativeConventionSource(sourcePath: string): boolean {
  const name = path.posix.basename(sourcePath);
  return /^(AGENTS|CLAUDE|CONTRIBUTING)\.md$/i.test(name)
    || /^package\.json$/i.test(name)
    || /^tsconfig(?:\.[^/]+)?\.json$/i.test(name)
    || /^(?:eslint\.config\.(?:js|cjs|mjs|ts)|\.eslintrc(?:\.(?:json|ya?ml|js|cjs))?)$/i.test(name)
    || /^(?:biome\.jsonc?|prettier\.config\.(?:js|cjs|mjs|ts)|\.prettierrc(?:\.(?:json|ya?ml|js|cjs))?|pyproject\.toml|Cargo\.toml)$/i.test(name)
    || /(^|\/)\.github\/workflows\/[^/]+\.ya?ml$/i.test(sourcePath);
}

function isGeneratedEvidencePath(sourcePath: string): boolean {
  return /(^|\/)(adapters|dist|build|coverage|vendor|node_modules)\//i.test(sourcePath);
}

function dedupeSynthesisEvidence(evidence: WikiSynthesisEvidence[]): WikiSynthesisEvidence[] {
  const values = new Map<string, WikiSynthesisEvidence>();
  for (const item of evidence) {
    const normalizedPath = normalize(item.path);
    const symbols = [...new Set(item.symbols ?? [])].sort();
    values.set(`${normalizedPath}\0${symbols.join("\0")}`, { path: normalizedPath, symbols });
  }
  return [...values.values()];
}

async function loadPrHistoryCache(repoRoot: string): Promise<PrHistoryCache | undefined> {
  try {
    const cachePath = await resolveExistingContainedPath(repoRoot, ".git/agentic-kit/pr-history/history.json", "repository root");
    const value = JSON.parse(await readFile(cachePath, "utf8")) as PrHistoryCache;
    if (value?.schemaVersion !== 1 || !Array.isArray(value.threads)) throw new Error("Invalid PR-history cache");
    return value;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return undefined;
    throw error;
  }
}

function validateReviewLesson(evidence: WikiReviewEvidence[], history: PrHistoryCache): void {
  const matched = evidence.map((reference) => {
    const thread = history.threads.find((candidate) => candidate.provider === reference.provider && candidate.pullRequest === reference.pullRequest && candidate.threadId === reference.threadId);
    if (!thread) throw new Error(`Review evidence is absent from the collected cache: ${reference.provider} PR #${reference.pullRequest}, thread ${reference.threadId}`);
    return thread;
  });
  const independentPrs = new Set(matched.map((thread) => `${thread.provider}:${thread.pullRequest}`));
  const acceptedChangeRequest = matched.some((thread) => /changes_requested|request.?changes/i.test(thread.reviewState ?? "") && thread.codeChangedAfter);
  const repeatedAccepted = independentPrs.size >= 2 && matched.every((thread) => thread.resolved || thread.codeChangedAfter);
  if (!repeatedAccepted && !acceptedChangeRequest) throw new Error("Review lesson needs accepted evidence from two independent PRs, or a request-changes review followed by a code change");
}

export async function auditWiki(options: WikiAuditOptions): Promise<WikiResult> {
  const profile = await inventoryRepository(options.repo);
  const findings = await collectWikiFindings(profile);
  return { status: findings.length ? "WIKI FINDINGS" : "WIKI AUDIT PASS", files: [], findings, profile };
}

export function renderWiki(profile: RepositoryProfile, split: WikiSplit): WikiFile[] {
  const optional = [...profile.signals].filter((signal) => signal !== "testing" && signal !== "architecture").sort();
  const workspacePages = split === "auto" && profile.workspaces.length > 1;
  const routeRows = [
    ["purpose, ownership, entry point, change route", "repository-map.md#repository-purpose", "Where work belongs", "repository tree"],
    ["architecture, boundary, flow, invariant", "engineering.md#ownership-and-dependencies", "How major parts interact", "manifests, entry points, workspaces"],
    ["setup, scripts, generation, verification", "engineering.md#verified-commands", "How to work and verify", "manifests, CI, configs"],
    ["implementation, naming, validation, api, configuration", "coding.md#evidenced-practices", "How repository code is shaped", "canonical source and configuration"],
    ["review, risk, evidence, maintainability", "reviewing.md#review-invariants", "What review must establish", "current source, diff, tests"],
    ["tests, fixtures, mocks, assertions", "testing.md#test-locations", "How behavior is tested", profile.testRoots.join(", ")],
    ["security, trust boundary, sensitive asset", "security.md#demonstrated-boundaries", "Which controls are demonstrated", "security-relevant source and tests"],
    ["file ownership, entry point", "repository-map.md#top-level-shape", "Where code and tests live", "repository tree"],
    ...optional.map((name) => [name.replace("-", ", "), `${name}.md#ownership-roots`, `${title(name)} conventions and boundaries`, sourceScopeFor(name)]),
  ];
  const workspaceLinks = workspacePages
    ? profile.workspaces.map((workspace) => `- [${workspace.name}](workspaces/${slug(workspace.name)}.md) — \`${workspace.path}\``)
    : split === "nested" && profile.workspaces.length > 1
      ? profile.workspaces.map((workspace) => `- [${workspace.name}](../${workspace.path}/.wiki/index.md) — closest wiki owns local guidance`)
      : [];
  const index = `${WIKI_MARKER}\n# Repository Wiki\n\nCurrent source and executable behavior are authoritative. Follow citations into live source; read only task-relevant sections.\n\n## Route by task\n\n| Task signals | Read |\n|---|---|\n${routeRows.map((row) => `| ${row[0]} | [${row[1]}](${row[1]}) |`).join("\n")}\n${workspaceLinks.length ? `\n## Workspaces\n\n${workspaceLinks.join("\n")}\n` : ""}\n## Wiki maintenance\n\nUse \`wiki reinit\`; never store task or session history.\n`;
  const topRows = topLevelRows(profile).map((row) => `| \`${row.path}\` | ${row.purpose} | \`${row.start}\` | ${row.tests ? `\`${row.tests}\`` : "—"} |`).join("\n");
  const repositoryMap = `${WIKI_MARKER}\n# Repository Map\n\n<a id="repository-purpose"></a>\n## Repository purpose\n\n${shapeSummary(profile)} This map routes work to tracked ownership, entry points, and tests.\n\n<a id="top-level-shape"></a>\n## Ownership and entry points\n\n| Path | Purpose | Start here | Nearest tests |\n|---|---|---|---|\n${topRows || "| `.` | Repository root | `.` | — |"}\n\n- Runtime entry points: ${inlinePaths(profile.entryPoints)}\n- Workspace owners: ${profile.workspaces.length ? profile.workspaces.map((item) => `\`${item.path}\``).join(", ") : "one repository root"}\n- Canonical/generated boundaries: ${profile.excludedRoots.length ? profile.excludedRoots.map((item) => `\`${item}/\``).join(", ") + " are not canonical source" : "no tracked generated or vendored root detected"}.\n- Tests: ${inlinePaths(profile.testRoots)}\n\n## Common change routes\n\n- Start at the owning entry point, follow callers to the boundary, then use the nearest listed tests.\n- For workspace changes, use its manifest and workspace-scoped commands.\n`;
  const engineering = `${WIKI_MARKER}\n# Engineering Guide\n\n<a id="ownership-and-dependencies"></a>\n## Ownership, dependencies, and flows\n\n- Ownership follows ${profile.workspaces.length ? profile.workspaces.map((item) => `\`${item.path}\` via \`${item.manifest}\``).join("; ") : "the primary repository build root"}.\n- Representative flow starts at ${inlinePaths(profile.entryPoints)} and crosses only boundaries evidenced by manifests and configuration.\n- External boundaries and invariants require focused source synthesis; do not infer them from inventory alone.\n\n<a id="verified-commands"></a>\n## Commands, generation, and verification\n\n| Purpose | Command | Evidence |\n|---|---|---|\n${profile.commands.length ? profile.commands.map((item) => `| ${item.purpose} | \`${escapeTable(item.command)}\` | \`${item.source}\` (${item.cwd}) |`).join("\n") : "| Repository inspection | `git status --short` | Git |"}\n\n- Manifests/configuration: ${inlinePaths(profile.manifests)}\n- CI verification: ${inlinePaths(profile.ciFiles)}\n- Generated outputs are not canonical source; run evidenced generation before final verification.\n`;
  const coding = `${WIKI_MARKER}\n# Coding Guide\n\n<a id="evidenced-practices"></a>\n## Evidenced practices\n\nInventory does not establish coding rules. Add no more than ten concise practices only after authoritative guidance or two independent current-code examples support syntax and branching, validation and errors, organization, naming, API reuse, state or configuration, and generated boundaries.\n`;
  const reviewing = `${WIKI_MARKER}\n# Reviewing Guide\n\n<a id="review-invariants"></a>\n## Review invariants and evidence\n\nVerify current ownership and boundaries, realistic changed-path risks, observable behavior, focused proof, generated drift, and maintainability. Follow cited source and do not treat this page or coding-rule repetition as standalone evidence.\n`;
  const testing = `${WIKI_MARKER}\n# Testing Guide\n\n<a id="test-locations"></a>\n## Test locations and commands\n\n- Locations and types: ${inlinePaths(profile.testRoots)}\n- Focused/full commands: ${profile.commands.filter((item) => /test|e2e/i.test(item.purpose)).map((item) => `\`${item.command}\` (\`${item.source}\`)`).join(", ") || "none deterministically grounded"}.\n- Naming, fixtures, mocks, assertions, expectations, and representative patterns require focused current-test evidence.\n`;
  const security = `${WIKI_MARKER}\n# Security Guide\n\n<a id="demonstrated-boundaries"></a>\n## Demonstrated boundaries and controls\n\nInventory alone demonstrates no trust boundary, sensitive asset, control, or security-relevant test. Record only those verified in current source and remain brief when none are found.\n`;
  const files: WikiFile[] = [
    { path: ".wiki/index.md", content: index, sourcePaths: profile.manifests.concat(profile.ciFiles) },
    { path: ".wiki/repository-map.md", content: repositoryMap, sourcePaths: profile.entryPoints.concat(profile.testRoots) },
    { path: ".wiki/engineering.md", content: engineering, sourcePaths: profile.manifests.concat(profile.ciFiles) },
    { path: ".wiki/coding.md", content: coding, sourcePaths: [] },
    { path: ".wiki/reviewing.md", content: reviewing, sourcePaths: [] },
    { path: ".wiki/testing.md", content: testing, sourcePaths: profile.testRoots.concat(profile.commands.filter((item) => /test|e2e/i.test(item.purpose)).map((item) => item.source)) },
    { path: ".wiki/security.md", content: security, sourcePaths: [] },
  ];
  for (const page of optional) files.push(renderOptionalPage(profile, page));
  if (workspacePages) for (const workspace of profile.workspaces) files.push(renderWorkspacePage(workspace));
  if (split === "nested" && profile.workspaces.length > 1) {
    for (const workspace of profile.workspaces) files.push(...renderNestedWorkspaceWiki(workspace));
  }
  for (const file of files) file.content = `${file.content.replace(WIKI_MARKER, wikiOwnershipHeader(file.path)).trimEnd()}\n\n${MANAGED_END}\n`;
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

export function validateWikiFiles(profile: RepositoryProfile, files: WikiFile[]): void {
  const tracked = new Set(profile.meaningfulFiles);
  const paths = new Set<string>();
  for (const file of files) {
    const normalizedPath = normalize(file.path);
    resolveContainedPath(profile.root, normalizedPath, "repository root");
    if (paths.has(normalizedPath)) throw new Error(`Duplicate wiki page: ${normalizedPath}`);
    paths.add(normalizedPath);
    if (!normalizedPath.includes("/.wiki/") && !normalizedPath.startsWith(".wiki/")) throw new Error(`Wiki page outside a wiki root: ${normalizedPath}`);
    if (/\.(features|memory)|task-history|session-state|handoff|reflection/i.test(normalizedPath)) throw new Error(`Forbidden durable knowledge surface: ${normalizedPath}`);
    if (file.content.charCodeAt(0) === 0xfeff) throw new Error(`UTF-8 BOM in ${normalizedPath}`);
    if (!hasExactWikiOwnershipHeader(file.content, normalizedPath)) throw new Error(`Missing exact wiki ownership header: ${normalizedPath}`);
    for (const sourcePath of file.sourcePaths) validateSourcePath(sourcePath, tracked, normalizedPath);
    if (file.content.startsWith("---\n")) {
      const frontmatter = parseFrontmatter<{ source_paths?: string[] }>(file.content);
      for (const sourcePath of frontmatter.data.source_paths ?? []) validateSourcePath(sourcePath, tracked, normalizedPath);
    }
    const words = wordCount(file.content);
    const budget = wikiWordBudget(normalizedPath);
    if (words > budget) throw new Error(`Wiki page exceeds ${budget}-word budget: ${normalizedPath}`);
    if (path.posix.basename(normalizedPath) === "repository-map.md" && repositoryPurposeWordCount(file.content) > 100) {
      throw new Error(`Repository purpose exceeds 100-word budget: ${normalizedPath}`);
    }
  }
  for (const wikiRoot of new Set(files.map((file) => wikiRootFor(file.path)))) {
    for (const page of REQUIRED_WIKI_PAGES) {
      if (!paths.has(`${wikiRoot}/${page}`)) throw new Error(`Missing required wiki page: ${wikiRoot}/${page}`);
    }
  }
  const generated = files.map((file) => ({ path: file.path, content: file.content, sourceId: `wiki:${file.path}` }));
  const broken = findBrokenLinks(generated);
  if (broken.length) throw new Error(`Broken generated wiki links:\n${broken.join("\n")}`);
  for (const command of profile.commands) {
    if (!tracked.has(command.source)) throw new Error(`Ungrounded command ${command.command}: ${command.source}`);
  }
}

async function applyWikiFiles(
  profile: RepositoryProfile,
  files: WikiFile[],
  dryRun: boolean,
  mode: "init" | "reinit",
  adoption: { adoptExisting?: boolean; confirmed?: boolean } = {},
): Promise<ApplyWikiResult> {
  const repoRoot = profile.root;
  const previous = await loadWikiInventory(repoRoot);
  const previousByPath = new Map(previous.files.map((item) => [item.path, item]));
  const legacyFiles = mode === "reinit" && previous.files.length === 0 ? await listExistingWikiFiles(repoRoot) : [];
  const adopting = Boolean(adoption.adoptExisting && legacyFiles.length);
  if (adoption.adoptExisting && previous.files.length > 0) throw new Error("--adopt-existing is only valid for an unowned legacy wiki");
  if (adopting && !dryRun && !adoption.confirmed) throw new Error("Legacy wiki adoption requires interactive confirmation or --yes");
  const conflicts: string[] = [];
  const mergedFiles: WikiFile[] = [];
  const backups: Array<{ path: string; content: string }> = [];
  const staleRemovals: Array<{ path: string; content: string }> = [];
  const findings: WikiFinding[] = [];
  const desiredPaths = new Set(files.map((file) => normalize(file.path)));
  if (adopting) {
    for (const legacy of legacyFiles) {
      backups.push(legacy);
      if (desiredPaths.has(legacy.path)) findings.push({ code: "LEGACY_PAGE_REPLACED", page: legacy.path.replace(/^\.wiki\//, ""), detail: "Existing unmarked page will be replaced from reviewed synthesis" });
      else {
        staleRemovals.push(legacy);
        findings.push({ code: "LEGACY_PAGE_DROPPED", page: legacy.path.replace(/^\.wiki\//, ""), detail: "Existing legacy page will be backed up and removed" });
      }
    }
  }
  for (const file of files) {
    const normalizedPath = normalize(file.path);
    try {
      const existingPath = await resolveExistingContainedPath(repoRoot, normalizedPath, "repository root");
      const existing = await readFile(existingPath, "utf8");
      const prior = previousByPath.get(normalizedPath);
      if (adopting) {
        mergedFiles.push(file);
        continue;
      } else if (prior) {
        if (prior.sourceId !== wikiSourceId(normalizedPath) || !hasExactWikiOwnershipHeader(existing, normalizedPath)) conflicts.push(normalizedPath);
        else if (sha256(existing) !== prior.sha256) {
          if (mode !== "reinit" || !existing.includes(MANAGED_END)) conflicts.push(normalizedPath);
          else {
            const human = existing.slice(existing.indexOf(MANAGED_END) + MANAGED_END.length).trim();
            const generated = file.content.trimEnd();
            mergedFiles.push({ ...file, content: human ? `${generated}\n\n${human}\n` : `${generated}\n` });
            backups.push({ path: normalizedPath, content: existing });
            continue;
          }
        } else if (mode === "reinit" && existing !== file.content) backups.push({ path: normalizedPath, content: existing });
      } else {
        conflicts.push(normalizedPath);
      }
      mergedFiles.push(file);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      mergedFiles.push(file);
    }
  }
  if (conflicts.length) throw new Error(`Human or locally modified wiki content conflict; refusing overwrite:\n${conflicts.join("\n")}`);
  if (mode === "reinit" && !adopting) {
    const desired = new Set(files.map((file) => normalize(file.path)));
    for (const prior of previous.files.filter((item) => !desired.has(item.path))) {
      try {
        const existingPath = await resolveExistingContainedPath(repoRoot, prior.path, "repository root");
        const existing = await readFile(existingPath, "utf8");
        const humanSuffix = existing.includes(MANAGED_END) ? existing.slice(existing.indexOf(MANAGED_END) + MANAGED_END.length).trim() : "";
        if (prior.sourceId === wikiSourceId(prior.path) && hasExactWikiOwnershipHeader(existing, prior.path) && sha256(existing) === prior.sha256 && !humanSuffix) {
          staleRemovals.push({ path: prior.path, content: existing });
          findings.push({ code: "STALE_PAGE_REMOVED", page: prior.path.replace(/^\.wiki\//, ""), detail: "No longer justified by current inventory or synthesis" });
        } else {
          findings.push({ code: "STALE_PAGE_CONFLICT", page: prior.path.replace(/^\.wiki\//, ""), detail: "Retained because managed content or human guidance was modified" });
        }
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      }
    }
  }
  validateWikiFiles(profile, mergedFiles);
  if (dryRun) return { findings };
  if (mode === "reinit") {
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const uniqueBackups = new Map(backups.concat(staleRemovals).map((item) => [item.path, item]));
    for (const backup of uniqueBackups.values()) await atomicWriteContained(repoRoot, `.git/agentic-kit/wiki-backups/${stamp}/${backup.path}`, backup.content, "repository root");
    for (const stale of staleRemovals) await unlinkContained(repoRoot, stale.path, "repository root");
  }
  for (const file of mergedFiles) await atomicWriteContained(repoRoot, file.path, file.content, "repository root");
  const merged = new Map(previous.files.map((item) => [item.path, item]));
  for (const stale of staleRemovals) merged.delete(stale.path);
  for (const file of mergedFiles) merged.set(normalize(file.path), await wikiInventoryEntry(repoRoot, file));
  const inventory: WikiInventory = {
    schemaVersion: 2,
    sourceRevision: await currentSourceRevision(repoRoot),
    files: [...merged.values()].sort((a, b) => a.path.localeCompare(b.path)),
  };
  await atomicWriteContained(repoRoot, WIKI_INVENTORY, `${JSON.stringify(inventory, null, 2)}\n`, "repository root");
  return { findings };
}

async function loadWikiInventory(repoRoot: string): Promise<WikiInventory> {
  try {
    const inventoryPath = await resolveExistingContainedPath(repoRoot, WIKI_INVENTORY, "repository root");
    const value = JSON.parse(await readFile(inventoryPath, "utf8")) as WikiInventory;
    if (![1, 2].includes(value.schemaVersion) || !Array.isArray(value.files) || value.files.some((item) =>
      !item
      || typeof item.path !== "string"
      || item.sourceId !== wikiSourceId(item.path)
      || !/^[a-f0-9]{64}$/.test(item.sha256)
      || (item.managedSha256 !== undefined && !/^[a-f0-9]{64}$/.test(item.managedSha256))
      || (value.schemaVersion === 2 && (!Array.isArray(item.evidence) || item.evidence.some((evidence) =>
        !evidence
        || typeof evidence.path !== "string"
        || !/^[a-f0-9]{64}$/.test(evidence.sha256)
        || !Array.isArray(evidence.symbols)
      )))
    )) throw new Error("wiki ownership inventory invalid");
    return value;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { schemaVersion: 1, files: [] };
    throw error;
  }
}

async function listExistingWikiFiles(repoRoot: string): Promise<Array<{ path: string; content: string }>> {
  const wikiRoot = path.join(repoRoot, ".wiki");
  let entries: Dirent<string>[];
  try {
    entries = await readdir(wikiRoot, { recursive: true, withFileTypes: true });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
  const files: Array<{ path: string; content: string }> = [];
  for (const entry of entries) {
    if (!entry.isFile()) continue;
    const absolute = path.join(entry.parentPath, entry.name);
    const relative = normalize(path.relative(repoRoot, absolute));
    files.push({ path: relative, content: await readFile(absolute, "utf8") });
  }
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

async function wikiInventoryEntry(repoRoot: string, file: WikiFile): Promise<WikiInventoryFile> {
  const evidenceByPath = new Map<string, Set<string>>();
  for (const item of [
    ...file.sourcePaths.map((sourcePath) => ({ path: sourcePath, symbols: [] as string[] })),
    ...(file.sourceEvidence ?? []),
  ]) {
    const evidencePath = normalize(item.path);
    const symbols = evidenceByPath.get(evidencePath) ?? new Set<string>();
    for (const symbol of item.symbols ?? []) symbols.add(symbol);
    evidenceByPath.set(evidencePath, symbols);
  }
  const receipts: WikiInventoryEvidence[] = [];
  for (const [evidencePath, symbols] of evidenceByPath) {
    const absolute = path.join(repoRoot, evidencePath);
    if (!(await lstat(absolute)).isFile()) continue;
    const source = await readFile(absolute, "utf8");
    receipts.push({ path: evidencePath, sha256: sha256(source), symbols: [...symbols].sort() });
  }
  const normalizedPath = normalize(file.path);
  return {
    path: normalizedPath,
    sourceId: wikiSourceId(normalizedPath),
    sha256: sha256(file.content),
    managedSha256: sha256(managedWikiContent(file.content)),
    evidence: receipts.sort((a, b) => a.path.localeCompare(b.path)),
  };
}

function managedWikiContent(content: string): string {
  const markerIndex = content.indexOf(MANAGED_END);
  return markerIndex < 0 ? content : content.slice(0, markerIndex + MANAGED_END.length);
}

async function currentSourceRevision(repoRoot: string): Promise<string> {
  try {
    const { stdout } = await execFile("git", ["-C", repoRoot, "rev-parse", "HEAD"], { encoding: "utf8" });
    return stdout.trim();
  } catch {
    return "UNBORN";
  }
}

async function collectVerifiedCommands(root: string, manifests: string[], ciFiles: string[], packageManager: "npm" | "pnpm" | "yarn"): Promise<VerifiedCommand[]> {
  const commands: VerifiedCommand[] = [];
  for (const manifest of manifests) {
    const source = await readFile(path.join(root, manifest), "utf8");
    if (manifest.endsWith("package.json")) {
      const json = JSON.parse(source) as { scripts?: Record<string, string> };
      const cwd = path.posix.dirname(manifest);
      commands.push({ purpose: "Install", command: scopedPackageCommand(packageManager, cwd, "install"), source: manifest, cwd });
      for (const [name] of Object.entries(json.scripts ?? {})) {
        if (/^(test|lint|build|typecheck|check|dev|start|e2e)(:|$)/.test(name)) commands.push({ purpose: title(name), command: scopedPackageCommand(packageManager, cwd, `run ${name}`), source: manifest, cwd });
      }
    } else if (manifest.endsWith("pyproject.toml")) {
      const toml = parseToml<Record<string, unknown>>(source);
      const cwd = path.posix.dirname(manifest);
      if (toml["build-system"]) commands.push({ purpose: "Build", command: cwd === "." ? "python -m build" : `python -m build ${cwd}`, source: manifest, cwd });
      if (toml.tool && typeof toml.tool === "object" && "pytest" in toml.tool) commands.push({ purpose: "Tests", command: cwd === "." ? "pytest" : `pytest ${cwd}`, source: manifest, cwd });
    } else if (manifest.endsWith("Cargo.toml")) {
      const cwd = path.posix.dirname(manifest);
      commands.push({ purpose: "Tests", command: cwd === "." ? "cargo test" : `cargo test --manifest-path ${manifest}`, source: manifest, cwd });
      commands.push({ purpose: "Build", command: cwd === "." ? "cargo build" : `cargo build --manifest-path ${manifest}`, source: manifest, cwd });
    } else if (manifest.endsWith("go.mod")) {
      const cwd = path.posix.dirname(manifest);
      commands.push({ purpose: "Tests", command: cwd === "." ? "go test ./..." : `go test ./${cwd}/...`, source: manifest, cwd });
      commands.push({ purpose: "Build", command: cwd === "." ? "go build ./..." : `go build ./${cwd}/...`, source: manifest, cwd });
    } else if (manifest.endsWith(".csproj")) {
      const cwd = path.posix.dirname(manifest);
      commands.push({ purpose: "Build", command: `dotnet build ${manifest}`, source: manifest, cwd });
      if (/test/i.test(manifest) || /tests?\//i.test(manifest)) commands.push({ purpose: "Tests", command: `dotnet test ${manifest}`, source: manifest, cwd });
    } else if (/(^|\/)(pom\.xml)$/.test(manifest)) {
      const cwd = path.posix.dirname(manifest);
      commands.push({ purpose: "Tests", command: cwd === "." ? "mvn test" : `mvn -f ${manifest} test`, source: manifest, cwd });
      commands.push({ purpose: "Build", command: cwd === "." ? "mvn package" : `mvn -f ${manifest} package`, source: manifest, cwd });
    } else if (/(^|\/)(build\.gradle(?:\.kts)?)$/.test(manifest)) {
      const cwd = path.posix.dirname(manifest);
      commands.push({ purpose: "Tests", command: cwd === "." ? "./gradlew test" : `./gradlew -p ${cwd} test`, source: manifest, cwd });
      commands.push({ purpose: "Build", command: cwd === "." ? "./gradlew build" : `./gradlew -p ${cwd} build`, source: manifest, cwd });
    }
  }
  for (const ciFile of ciFiles) {
    try {
      collectRunCommands(parseYaml(await readFile(path.join(root, ciFile), "utf8")), ciFile, commands);
    } catch {
      // A non-YAML CI file remains evidence of CI presence but not a command source.
    }
  }
  const unique = new Map(commands.map((item) => [`${item.command}\0${item.source}`, item]));
  return [...unique.values()].sort((a, b) => a.purpose.localeCompare(b.purpose) || a.command.localeCompare(b.command));
}

async function detectWorkspaces(root: string, manifests: string[], trackedFiles: string[], packageManager: "npm" | "pnpm" | "yarn"): Promise<WorkspaceProfile[]> {
  const nested = manifests.filter((manifest) => manifest.includes("/") && /(^|\/)(package\.json|pyproject\.toml|Cargo\.toml|go\.mod|[^/]+\.csproj)$/.test(manifest));
  const declaredPatterns = await rootWorkspacePatterns(root, trackedFiles);
  const workspaces: WorkspaceProfile[] = [];
  for (const manifest of nested) {
    const workspacePath = path.posix.dirname(manifest);
    const declaration = workspaceDeclarationState(workspacePath, declaredPatterns);
    if (declaration.excluded) continue;
    const independent = await hasIndependentWorkspaceEvidence(root, manifest, workspacePath, trackedFiles);
    if (!declaration.included && !independent) continue;
    const name = path.posix.basename(workspacePath);
    const commands = await collectVerifiedCommands(root, [manifest], [], packageManager);
    workspaces.push({ name, path: workspacePath, manifest, commands });
  }
  return workspaces.sort((a, b) => a.path.localeCompare(b.path));
}

async function detectPackageManager(root: string, trackedFiles: string[]): Promise<"npm" | "pnpm" | "yarn"> {
  if (trackedFiles.includes("package.json")) {
    const pkg = JSON.parse(await readFile(path.join(root, "package.json"), "utf8")) as { packageManager?: string };
    const declared = pkg.packageManager?.split("@", 1)[0];
    if (declared === "pnpm" || declared === "yarn" || declared === "npm") return declared;
  }
  const evidence = new Set<"npm" | "pnpm" | "yarn">();
  if (trackedFiles.includes("pnpm-lock.yaml") || trackedFiles.includes("pnpm-workspace.yaml")) evidence.add("pnpm");
  if (trackedFiles.includes("yarn.lock")) evidence.add("yarn");
  if (trackedFiles.includes("package-lock.json")) evidence.add("npm");
  if (evidence.size > 1) throw new Error(`Ambiguous package manager: conflicting lockfiles for ${[...evidence].join(", ")}`);
  return evidence.values().next().value ?? "npm";
}

function scopedPackageCommand(packageManager: "npm" | "pnpm" | "yarn", cwd: string, operation: string): string {
  if (cwd === ".") return `${packageManager} ${operation}`;
  if (packageManager === "npm") return `npm --prefix ${cwd} ${operation}`;
  if (packageManager === "pnpm") return `pnpm --dir ${cwd} ${operation}`;
  return `yarn --cwd ${cwd} ${operation}`;
}

async function rootWorkspacePatterns(root: string, trackedFiles: string[]): Promise<string[]> {
  const patterns: string[] = [];
  if (trackedFiles.includes("package.json")) {
    const pkg = JSON.parse(await readFile(path.join(root, "package.json"), "utf8")) as { workspaces?: string[] | { packages?: string[] } };
    if (Array.isArray(pkg.workspaces)) patterns.push(...pkg.workspaces);
    else if (pkg.workspaces?.packages) patterns.push(...pkg.workspaces.packages);
  }
  if (trackedFiles.includes("pnpm-workspace.yaml")) {
    const config = parseYaml<{ packages?: string[] }>(await readFile(path.join(root, "pnpm-workspace.yaml"), "utf8"));
    patterns.push(...config.packages ?? []);
  }
  if (trackedFiles.includes("Cargo.toml")) {
    const cargo = parseToml<{ workspace?: { members?: string[] } }>(await readFile(path.join(root, "Cargo.toml"), "utf8"));
    patterns.push(...cargo.workspace?.members ?? []);
  }
  return patterns.map(normalize);
}

async function hasIndependentWorkspaceEvidence(root: string, manifest: string, workspacePath: string, trackedFiles: string[]): Promise<boolean> {
  const source = await readFile(path.join(root, manifest), "utf8");
  if (manifest.endsWith("package.json")) {
    const pkg = JSON.parse(source) as { scripts?: Record<string, string> };
    if (Object.keys(pkg.scripts ?? {}).some((name) => /^(build|test|start|dev|e2e)(:|$)/.test(name))) return true;
  } else if (manifest.endsWith("pyproject.toml")) {
    const config = parseToml<Record<string, unknown>>(source);
    if (config["build-system"] || config.project) return true;
  } else if (/Cargo\.toml|go\.mod|\.csproj$/.test(manifest)) return true;
  return trackedFiles.some((file) => file.startsWith(`${workspacePath}/`) && /(^|\/)(Dockerfile|compose\.ya?ml|Chart\.yaml)$/.test(file));
}

function matchesWorkspacePattern(workspacePath: string, pattern: string): boolean {
  return picomatch(normalize(pattern), { dot: true, nonegate: true })(workspacePath);
}

function workspaceDeclarationState(workspacePath: string, patterns: string[]): { included: boolean; excluded: boolean } {
  let included = false;
  let excluded = false;
  for (const rawPattern of patterns) {
    const negated = rawPattern.startsWith("!");
    const pattern = negated ? rawPattern.slice(1) : rawPattern;
    if (!matchesWorkspacePattern(workspacePath, pattern)) continue;
    included = !negated;
    excluded = negated;
  }
  return { included, excluded };
}

async function collectWikiFindings(profile: RepositoryProfile): Promise<WikiFinding[]> {
  const findings: WikiFinding[] = [];
  for (const legacy of (await listExistingWikiFiles(profile.root)).filter((item) => /(?:^|\/)(?:\.features|[^/]*(?:memory|reflection|handoff|task-history)[^/]*)$/i.test(item.path))) {
    findings.push({ code: "LEGACY_KNOWLEDGE", page: legacy.path.replace(/^\.wiki\//, ""), detail: "Legacy memory, feature, reflection, handoff, or task-history content is not repository wiki knowledge" });
  }
  const inventory = await loadWikiInventory(profile.root);
  const inventoryByPath = new Map(inventory.files.map((file) => [file.path, file]));
  const wikiRoots = new Set([".wiki", ...inventory.files.map((file) => wikiRootFor(file.path))]);
  for (const workspace of profile.workspaces) {
    if (await fileExists(path.join(profile.root, workspace.path, ".wiki"))) wikiRoots.add(`${workspace.path}/.wiki`);
  }
  const allContents = new Map<string, string>();
  for (const wikiRoot of [...wikiRoots].sort()) {
    const contents = await readWikiRoot(profile.root, wikiRoot);
    const names = [...contents.keys()];
    const display = (page: string): string => wikiRoot === ".wiki" ? page : `${wikiRoot}/${page}`;
    for (const [page, content] of contents) {
      const wikiPath = `${wikiRoot}/${page}`;
      allContents.set(wikiPath, content);
      if (!hasExactWikiOwnershipHeader(content, wikiPath) || !content.includes(MANAGED_END)) {
        findings.push({ code: "INVALID_OWNERSHIP", page: display(page), detail: "Managed wiki ownership header or boundary is missing" });
      }
      const owned = inventoryByPath.get(wikiPath);
      if (!owned) findings.push({ code: "MISSING_OWNERSHIP", page: display(page), detail: "Page is absent from the managed wiki inventory" });
      else if (owned.managedSha256 && sha256(managedWikiContent(content)) !== owned.managedSha256) {
        findings.push({ code: "MODIFIED_MANAGED_CONTENT", page: display(page), detail: "Managed wiki content differs from the ownership inventory" });
      }
    }
    for (const required of REQUIRED_WIKI_PAGES) {
      if (!contents.has(required)) findings.push({ code: "MISSING_REQUIRED_PAGE", page: display(required), detail: `Required wiki page ${wikiRoot}/${required} is missing` });
    }
    const index = contents.get("index.md") ?? "";
    for (const match of index.matchAll(/\]\(([^)#]+)#([a-z][a-z0-9-]+)\)/g)) {
      const targetPage = normalize(match[1]!);
      const target = contents.get(targetPage);
      if (!target?.includes(`<a id="${match[2]}"></a>`)) findings.push({ code: "BROKEN_ANCHOR", page: display("index.md"), detail: `${targetPage}#${match[2]}` });
    }
    for (const page of names.filter((name) => name !== "index.md" && !name.startsWith("workspaces/"))) {
      if (!index.includes(page)) findings.push({ code: "UNINDEXED_PAGE", page: display(page), detail: "Page is not routed by index.md" });
    }
    for (const [page, content] of contents) {
      for (const id of [...content.matchAll(/<a id="([a-z][a-z0-9-]+)"><\/a>/g)].map((match) => match[1]!)) {
        if (page !== "index.md" && !index.includes(`${page}#${id}`)) findings.push({ code: "UNROUTED_SECTION", page: display(page), detail: `${page}#${id}` });
      }
    }
  }
  const generated = [...allContents].map(([wikiPath, content]) => ({ path: wikiPath, content, sourceId: `wiki:${wikiPath}` }));
  for (const broken of findBrokenLinks(generated)) {
    const [source, target] = broken.split(" -> ");
    const content = allContents.get(source!);
    findings.push({ code: "BROKEN_LINK", page: source!.replace(/^\.wiki\//, ""), detail: target!, line: content ? lineContaining(content, target!) : undefined });
  }
  for (const file of inventory.files) {
    for (const evidence of file.evidence ?? []) {
      try {
        const sourcePath = await resolveExistingContainedPath(profile.root, evidence.path, "repository root");
        const source = await readFile(sourcePath, "utf8");
        if (sha256(source) !== evidence.sha256) findings.push({ code: "STALE_EVIDENCE", page: file.path.replace(/^\.wiki\//, ""), detail: evidence.path });
        for (const symbol of evidence.symbols) if (!source.includes(symbol)) findings.push({ code: "MISSING_SYMBOL", page: file.path.replace(/^\.wiki\//, ""), detail: `${evidence.path}#${symbol}` });
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code === "ENOENT") findings.push({ code: "MISSING_EVIDENCE", page: file.path.replace(/^\.wiki\//, ""), detail: evidence.path });
        else throw error;
      }
    }
  }
  const seenByRoot = new Map<string, Map<string, string>>();
  for (const [wikiPath, content] of allContents) {
    const page = wikiPath.startsWith(".wiki/") ? wikiPath.slice(".wiki/".length) : wikiPath;
    const wikiRoot = wikiRootFor(wikiPath);
    const seen = seenByRoot.get(wikiRoot) ?? new Map<string, string>();
    seenByRoot.set(wikiRoot, seen);
    const lines = content.split(/\r?\n/);
    const budget = wikiWordBudget(wikiPath);
    const words = wordCount(content);
    if (words > budget) findings.push({ code: "OVERSIZED_PAGE", page, detail: `${words} words exceeds ${budget}` });
    if (path.posix.basename(wikiPath) === "repository-map.md" && repositoryPurposeWordCount(content) > 100) findings.push({ code: "OVERSIZED_PURPOSE", page, detail: "Repository purpose exceeds 100 words" });
    lines.forEach((line, indexNumber) => {
      for (const match of line.matchAll(/`([^`]+[\/][^`]*)`/g)) {
        const candidate = normalize(match[1]!);
        if (/[*?\[\]]/.test(candidate) || candidate.startsWith("http")) continue;
        const candidatePath = candidate.split("#", 1)[0]!;
        const trackedDirectory = profile.trackedFiles.some((file) => file.startsWith(`${candidatePath.replace(/\/$/, "")}/`));
        const verifiedCommand = profile.commands.some((item) => item.command === candidate);
        if (!profile.trackedFiles.includes(candidatePath) && !trackedDirectory && !verifiedCommand && !candidate.startsWith("npm ") && !candidate.startsWith("python ")) findings.push({ code: "MISSING_PATH", page, detail: candidate, line: indexNumber + 1 });
      }
      const normalizedLine = line.trim().toLowerCase();
      if (normalizedLine.length > 35 && !normalizedLine.startsWith("|") && !normalizedLine.startsWith("-") && !normalizedLine.startsWith("<!--") && !normalizedLine.startsWith("evidence:")) {
        const prior = seen.get(normalizedLine);
        if (prior && prior !== page) findings.push({ code: "DUPLICATE_GUIDANCE", page, detail: `Duplicates ${prior}`, line: indexNumber + 1 });
        else seen.set(normalizedLine, page);
      }
      if (/\b(best practices|clean code|write good tests)\b/i.test(line)) findings.push({ code: "GENERIC_GUIDANCE", page, detail: line.trim(), line: indexNumber + 1 });
      for (const command of extractDocumentedCommands(line)) if (!profile.commands.some((item) => item.command === command)) findings.push({ code: "STALE_COMMAND", page, detail: command, line: indexNumber + 1 });
    });
  }
  return findings.sort((a, b) => a.page.localeCompare(b.page) || a.code.localeCompare(b.code) || (a.line ?? 0) - (b.line ?? 0));
}

async function readWikiRoot(repoRoot: string, wikiRoot: string): Promise<Map<string, string>> {
  const absoluteRoot = path.join(repoRoot, wikiRoot);
  let entries: Dirent<string>[];
  try {
    entries = await readdir(absoluteRoot, { recursive: true, withFileTypes: true });
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return new Map();
    throw error;
  }
  const contents = new Map<string, string>();
  for (const entry of entries) {
    if (!entry.isFile() || !entry.name.endsWith(".md")) continue;
    const absolute = path.join(entry.parentPath, entry.name);
    contents.set(normalize(path.relative(absoluteRoot, absolute)), await readFile(absolute, "utf8"));
  }
  return contents;
}

function renderOptionalPage(profile: RepositoryProfile, page: string): WikiFile {
  if (page === "architecture") {
    const sources = [...new Set(profile.workspaces.map((item) => item.manifest).concat(profile.manifests, profile.entryPoints))].slice(0, 40);
    const body = `${WIKI_MARKER}\n# Architecture\n\n<a id="workspace-boundaries"></a>\n## Workspace boundaries\n\n${profile.workspaces.map((item) => `- \`${item.path}\` is independently manifested by \`${item.manifest}\`.`).join("\n") || "- The repository has one primary build root."}\n\n## Runtime entry points\n\n${bulletPaths(profile.entryPoints)}\n\n## Verification\n\n${profile.workspaces.flatMap((item) => item.commands).map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- Workspace manifests are the current boundary evidence."}\n`;
    return { path: ".wiki/architecture.md", content: serializeFrontmatter({ use_when: ["architecture", "workspace", "boundary"], source_paths: sources }, body), sourcePaths: sources };
  }
  const area = profile.areas[page]!;
  const sourcePaths = [...new Set(area.sources.concat(area.tests, area.commands.map((item) => item.source)))];
  const body = `${WIKI_MARKER}\n# ${title(page)}\n\n<a id="ownership-roots"></a>\n## Ownership roots\n\n${bulletPaths(area.roots)}\n\n## Entry points and flow evidence\n\n${bulletPaths(area.sources)}\n\n## Tests\n\n${bulletPaths(area.tests)}\n\n## Verified commands\n\n${area.commands.map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- Area verification is grounded by the listed tracked tests."}\n`;
  return { path: `.wiki/${page}.md`, content: serializeFrontmatter({ use_when: page.split("-"), source_paths: sourcePaths }, body), sourcePaths };
}

function renderTestingPage(profile: RepositoryProfile): WikiFile {
  const sources = profile.testRoots;
  const body = `${WIKI_MARKER}\n# Testing\n\n<a id="test-locations"></a>\n## Test locations\n\n${bulletPaths(sources)}\n\n## Verified commands\n\n${profile.commands.filter((item) => /test|e2e/i.test(item.purpose)).map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- No test command was deterministically grounded; inspect maintained CI before running one."}\n`;
  return { path: ".wiki/testing.md", content: serializeFrontmatter({ use_when: ["test", "fixture", "e2e"], source_paths: sources }, body), sourcePaths: sources };
}

function renderWorkspacePage(workspace: WorkspaceProfile): WikiFile {
  const body = `${WIKI_MARKER}\n# ${workspace.name} Workspace\n\n## Purpose and boundary\n\n\`${workspace.path}\` is independently manifested by \`${workspace.manifest}\`.\n\n## Verified commands\n\n${workspace.commands.map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- No workspace-local command was grounded."}\n`;
  return { path: `.wiki/workspaces/${slug(workspace.name)}.md`, content: serializeFrontmatter({ use_when: [workspace.name], source_paths: [workspace.manifest] }, body), sourcePaths: [workspace.manifest] };
}

function renderNestedWorkspaceWiki(workspace: WorkspaceProfile): WikiFile[] {
  const prefix = `${workspace.path}/.wiki`;
  const index = `${WIKI_MARKER}\n# ${workspace.name} Wiki\n\nCurrent source is authoritative; follow citations into live source.\n\n- Purpose and ownership: [repository map](repository-map.md#repository-purpose)\n- Boundaries and commands: [engineering](engineering.md#ownership-and-dependencies)\n- Implementation: [coding](coding.md#evidenced-practices)\n- Review: [reviewing](reviewing.md#review-invariants)\n- Tests: [testing](testing.md#test-locations)\n- Security: [security](security.md#demonstrated-boundaries)\n`;
  const map = `${WIKI_MARKER}\n# Repository Map\n\n<a id="repository-purpose"></a>\n## Repository purpose\n\nThe \`${workspace.path}\` workspace is independently manifested by \`${workspace.manifest}\`.\n\n## Ownership, entry points, and change routes\n\nStart at the workspace source, follow its callers and boundaries, and verify with workspace commands and nearest tests. Generated output is not canonical source.\n`;
  const engineering = `${WIKI_MARKER}\n# Engineering Guide\n\n<a id="ownership-and-dependencies"></a>\n## Ownership, dependencies, flows, and invariants\n\nThe manifest \`${workspace.manifest}\` defines this workspace boundary. Focused synthesis must establish dependency direction, external boundaries, representative flows, and invariants from live source.\n\n## Commands, generation, and verification\n\n${workspace.commands.map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- No workspace-local command was grounded."}\n`;
  const coding = `${WIKI_MARKER}\n# Coding Guide\n\n<a id="evidenced-practices"></a>\n## Evidenced practices\n\nRecord at most ten workspace-specific practices only when authoritative guidance or two independent current-code examples support them.\n`;
  const reviewing = `${WIKI_MARKER}\n# Reviewing Guide\n\n<a id="review-invariants"></a>\n## Review invariants\n\nVerify workspace ownership, boundaries, realistic risks, current evidence, generated drift, and maintainability without duplicating coding rules.\n`;
  const testing = `${WIKI_MARKER}\n# Testing Guide\n\n<a id="test-locations"></a>\n## Test locations and commands\n\n${workspace.commands.filter((item) => /test|e2e/i.test(item.purpose)).map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- No workspace-local test command was grounded."}\n\nFocused synthesis must establish actual test types, names, fixtures, mocks, assertions, expectations, and representative patterns.\n`;
  const security = `${WIKI_MARKER}\n# Security Guide\n\n<a id="demonstrated-boundaries"></a>\n## Demonstrated boundaries and controls\n\nRecord only workspace trust boundaries, controls, sensitive assets, and security tests demonstrated in current source.\n`;
  return [
    { path: `${prefix}/index.md`, content: index, sourcePaths: [workspace.manifest] },
    { path: `${prefix}/repository-map.md`, content: map, sourcePaths: [workspace.manifest] },
    { path: `${prefix}/engineering.md`, content: engineering, sourcePaths: [workspace.manifest] },
    { path: `${prefix}/coding.md`, content: coding, sourcePaths: [] },
    { path: `${prefix}/reviewing.md`, content: reviewing, sourcePaths: [] },
    { path: `${prefix}/testing.md`, content: testing, sourcePaths: workspace.commands.filter((item) => /test|e2e/i.test(item.purpose)).map((item) => item.source) },
    { path: `${prefix}/security.md`, content: security, sourcePaths: [] },
  ];
}

function topLevelRows(profile: RepositoryProfile): Array<{ path: string; purpose: string; start: string; tests?: string }> {
  const roots = new Map<string, string[]>();
  for (const file of profile.meaningfulFiles) {
    const segment = file.includes("/") ? `${file.split("/")[0]}/` : ".";
    const list = roots.get(segment) ?? [];
    list.push(file);
    roots.set(segment, list);
  }
  return [...roots].slice(0, 20).map(([root, files]) => ({
    path: root,
    purpose: root === "." ? "Repository configuration and root entry points" : purposeForRoot(root),
    start: files.find((file) => profile.entryPoints.includes(file)) ?? files.find(isManifest) ?? files[0]!,
    tests: files.find(isTestFile),
  }));
}

function collectRunCommands(value: unknown, source: string, output: VerifiedCommand[]): void {
  if (Array.isArray(value)) for (const item of value) collectRunCommands(item, source, output);
  else if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      if (key === "run" && typeof item === "string" && item.length < 300 && !item.includes("\n")) output.push({ purpose: "CI", command: item.trim(), source, cwd: "." });
      else collectRunCommands(item, source, output);
    }
  }
}

function validateSourcePath(sourcePath: string, tracked: Set<string>, page: string): void {
  const normalized = normalize(sourcePath);
  if (/[*?\[\]]/.test(normalized)) throw new Error(`Glob source path is not allowed in ${page}: ${normalized}`);
  if (!tracked.has(normalized) && !(normalized.endsWith("/") && [...tracked].some((file) => file.startsWith(normalized)))) throw new Error(`Missing source path in ${page}: ${normalized}`);
}

function findBrokenLinks(files: Array<{ path: string; content: string; sourceId: string }>): string[] {
  return findBrokenLocalMarkdownLinks(files);
}

function isManifest(file: string): boolean {
  return /(^|\/)(package\.json|pyproject\.toml|Cargo\.toml|go\.mod|[^/]+\.(sln|csproj)|pom\.xml|build\.gradle(?:\.kts)?)$/.test(file);
}

function isTestFile(file: string): boolean {
  return /(^|\/)(__tests__|tests?|e2e|spec)(\/|\.)|\.(test|spec)\.[^.]+$/.test(file);
}

function testRootFor(file: string): string {
  const parts = file.split("/");
  const index = parts.findIndex((part) => /^(tests?|__tests__|e2e|spec)$/.test(part));
  return index >= 0 ? `${parts.slice(0, index + 1).join("/")}/` : file;
}

function isEntryPoint(file: string): boolean {
  return /(^|\/)(main|index|app|server|cli|worker)\.(ts|tsx|js|jsx|py|go|rs|java|cs|swift)$/.test(file) || /(^|\/)src\/lib\.rs$/.test(file);
}

function isBinaryNoise(file: string): boolean {
  return /\.(png|jpe?g|gif|webp|ico|pdf|zip|tar|gz|woff2?|ttf|mp4|mov|exe|dll|so|dylib|lock)$/i.test(file) && !/(package-lock|pnpm-lock|yarn\.lock)/.test(file);
}

function languageFor(file: string): string {
  const map: Record<string, string> = { ".ts": "TypeScript", ".tsx": "TypeScript", ".js": "JavaScript", ".jsx": "JavaScript", ".py": "Python", ".go": "Go", ".rs": "Rust", ".java": "Java", ".kt": "Kotlin", ".cs": "C#", ".swift": "Swift", ".rb": "Ruby", ".php": "PHP" };
  return map[path.posix.extname(file).toLowerCase()] ?? "";
}

function purposeForRoot(root: string): string {
  if (/^(src|lib)\/$/.test(root)) return "Primary source";
  if (/^(tests?|e2e)\/$/.test(root)) return "Tests and fixtures";
  if (/^(apps|packages)\/$/.test(root)) return "Workspace roots";
  if (root === ".github/") return "Automation and CI";
  return "Tracked repository area";
}

function shapeSummary(profile: RepositoryProfile): string {
  const runtime = profile.languages.length ? profile.languages.join(", ") : "documentation/configuration";
  const workspace = profile.workspaces.length > 1 ? `monorepo with ${profile.workspaces.length} independently manifested workspaces` : "single-root repository";
  return `${title(profile.size)} ${workspace}; primary tracked languages: ${runtime}.`;
}

function sourceScopeFor(page: string): string {
  return page === "architecture" ? "manifests, entry points, workspaces" : `actual ${page.replace("-", " ")} paths`;
}

function bulletPaths(paths: string[]): string {
  return paths.length ? paths.map((item) => `- \`${item}\``).join("\n") : "- No applicable tracked path was detected.";
}

function inlinePaths(paths: string[]): string {
  return paths.length ? paths.map((item) => `\`${item}\``).join(", ") : "none deterministically detected";
}

function title(value: string): string {
  return value.split(/[-_:]/).map((part) => part ? `${part[0]!.toUpperCase()}${part.slice(1)}` : part).join(" ");
}

function slug(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

function escapeTable(value: string): string {
  return value.replace(/\|/g, "\\|").replace(/`/g, "\\`");
}

function lineContaining(content: string, value: string): number | undefined {
  const index = content.split(/\r?\n/).findIndex((line) => line.includes(value));
  return index >= 0 ? index + 1 : undefined;
}

function extractDocumentedCommands(line: string): string[] {
  const candidates = line.match(/`([^`]+)`/g)?.map((value) => value.slice(1, -1)) ?? [];
  return candidates.filter((value) => /^(npm|pnpm|yarn|python|pytest|cargo|go|dotnet|mvn|\.\/gradlew)\s/.test(value));
}

function normalize(value: string): string {
  return value.split(path.sep).join("/").replace(/^\.\//, "");
}

function sha256(content: string): string {
  return createHash("sha256").update(content, "utf8").digest("hex");
}

function wikiSourceId(filePath: string): string {
  return `wiki:${normalize(filePath)}`;
}

function wikiOwnershipHeader(filePath: string): string {
  return `<!-- agentic-coding-kit-wiki:generated schema=${WIKI_SCHEMA_VERSION} type=repository-wiki source=${wikiSourceId(filePath)} -->`;
}

function hasExactWikiOwnershipHeader(content: string, filePath: string): boolean {
  const expected = wikiOwnershipHeader(filePath);
  const previous = expected.replace(`schema=${WIKI_SCHEMA_VERSION}`, "schema=1");
  return content.replace(/\r\n/g, "\n").split("\n").some((line) => line === expected || line === previous);
}

function wordCount(content: string): number {
  return content.match(/\S+/g)?.length ?? 0;
}

function repositoryPurposeWordCount(content: string): number {
  const start = content.indexOf('<a id="repository-purpose"></a>');
  if (start < 0) return 0;
  const bodyStart = content.indexOf("\n", content.indexOf("## ", start));
  if (bodyStart < 0) return 0;
  const nextSection = content.indexOf("\n## ", bodyStart + 1);
  return wordCount(content.slice(bodyStart, nextSection < 0 ? undefined : nextSection));
}

function wikiWordBudget(filePath: string): number {
  const name = path.posix.basename(normalize(filePath)) as (typeof REQUIRED_WIKI_PAGES)[number];
  if (name in WIKI_WORD_BUDGETS) return WIKI_WORD_BUDGETS[name];
  return 600;
}

function wikiRootFor(filePath: string): string {
  const normalized = normalize(filePath);
  const marker = normalized.lastIndexOf("/.wiki/");
  return marker >= 0 ? normalized.slice(0, marker + "/.wiki".length) : ".wiki";
}

async function fileExists(filePath: string): Promise<boolean> {
  try {
    const stat = await lstat(filePath);
    return stat.isFile();
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
    throw error;
  }
}

function deriveAreas(files: string[], testRoots: string[], commands: VerifiedCommand[], workspaces: WorkspaceProfile[]): Record<string, AreaProfile> {
  const definitions: Record<string, RegExp> = {
    frontend: /(^|\/)(web|frontend|client|ui)(\/|$)|\.(tsx|jsx)$/i,
    backend: /(^|\/)(api|backend|server|services?)(\/|$)|(^|\/)(server|app)\.(ts|js|py)$/i,
    api: /(^|\/)(api|routes?|controllers?|endpoints?|openapi|graphql)(\/|$)|api[-_.]?client/i,
    "auth-security": /(^|\/)(auth|security|permissions?|sessions?|identity)(\/|$)|oauth|jwt|csrf/i,
    data: /(^|\/)(data|database|db|models?|migrations?|repositories)(\/|$)|schema|prisma|drizzle/i,
    integrations: /(^|\/)(integrations?|adapters?|connectors?|webhooks?)(\/|$)|http[-_.]?client/i,
    ipc: /(^|\/)(ipc|bridge|preload|tunnels?|proxy)(\/|$)|named[-_.]?pipe/i,
    jobs: /(^|\/)(jobs?|workers?|queues?|scheduler|cron)(\/|$)/i,
    observability: /(^|\/)(observability|telemetry|logging|metrics|tracing)(\/|$)/i,
    deployment: /(^|\/)(deploy|deployment|infra|terraform|charts?)(\/|$)|Dockerfile|compose\.ya?ml/i,
    "ai-ml": /(^|\/)(ai|ml|prompts?|evals?)(\/|$)|openai|anthropic|langchain|llama/i,
    desktop: /(^|\/)(desktop|electron|tauri)(\/|$)|electron|tauri/i,
    cli: /(^|\/)(cli|bin|commands?)(\/|$)/i,
  };
  const areas: Record<string, AreaProfile> = {};
  for (const [id, pattern] of Object.entries(definitions)) {
    const sources = files.filter((file) => SOURCE_EXTENSIONS.has(path.posix.extname(file).toLowerCase()) && !isTestFile(file) && pattern.test(file));
    if (!sources.length) continue;
    const roots = [...new Set(sources.map((file) => workspaces.find((workspace) => file.startsWith(`${workspace.path}/`))?.path ?? "."))].sort();
    const tests = files.filter((file) => isTestFile(file) && (pattern.test(file) || roots.some((root) => root !== "." && file.startsWith(`${root}/`))));
    const areaCommands = commands.filter((command) => roots.includes(".") ? !command.source.includes("/") : roots.some((root) => command.source.startsWith(`${root}/`)));
    areas[id] = { id, roots, sources: sources.slice(0, 40), tests: tests.slice(0, 30), commands: areaCommands.slice(0, 20) };
  }
  return areas;
}

function isSubstantiveArea(area: AreaProfile): boolean {
  return area.sources.length > 0 && (area.sources.length > 1 || area.tests.length > 0 || area.commands.length > 0);
}
