import { execFile as execFileCallback } from "node:child_process";
import { createHash } from "node:crypto";
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
const WIKI_SCHEMA_VERSION = 1;
const WIKI_INVENTORY = ".git/agentic-kit/wiki-generated.json";
const MANAGED_END = "<!-- agentic-coding-kit-wiki:managed-end -->";
const NOISE_SEGMENTS = new Set([".git", ".kit", ".wiki", ".agentic-kit-backup", "node_modules", "vendor", "dist", "build", "coverage", "cache", ".cache", "target"]);
const SOURCE_EXTENSIONS = new Set([".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".rs", ".java", ".kt", ".cs", ".swift", ".rb", ".php"]);

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

export interface WikiFile { path: string; content: string; sourcePaths: string[] }
export interface WikiInitOptions { repo: string; wikiSplit: WikiSplit; dryRun: boolean; synthesis?: string; prHistory?: PrHistoryMode; prHistoryConsented?: boolean; interactive?: boolean }
export interface WikiAuditOptions { repo: string }
export interface WikiResult { status: string; files: string[]; findings?: WikiFinding[]; profile?: RepositoryProfile }
export interface WikiFinding { code: string; page: string; detail: string; line?: number }

interface WikiInventory { schemaVersion: 1; files: Array<{ path: string; sourceId: string; sha256: string }> }
interface WikiSynthesisEvidence { path: string; symbols?: string[] }
interface WikiReviewEvidence { provider: "github" | "azure"; pullRequest: number; threadId: string }
interface WikiSynthesisSection { heading: string; body: string; evidence: WikiSynthesisEvidence[]; reviewEvidence?: WikiReviewEvidence[] }
interface WikiSynthesisPage { page: string; sections: WikiSynthesisSection[] }
interface WikiSynthesis { schemaVersion: 1; pages: WikiSynthesisPage[] }
interface ApplyWikiResult { findings: WikiFinding[] }

export async function inventoryRepository(repo: string): Promise<RepositoryProfile> {
  const root = path.resolve(repo);
  const { stdout } = await execFile("git", ["-C", root, "ls-files", "-z"], { encoding: "utf8", maxBuffer: 10 * 1024 * 1024 });
  const indexedFiles = stdout.split("\0").filter(Boolean).map(normalize).sort();
  const trackedFiles = (await Promise.all(indexedFiles.map(async (file) => await fileExists(path.join(root, file)) ? file : undefined))).filter((file): file is string => Boolean(file));
  const excludedRoots = [...new Set(trackedFiles.flatMap((file) => file.split("/").filter((segment) => NOISE_SEGMENTS.has(segment))))].sort();
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
  const profile = await inventoryRepository(options.repo);
  const history = await collectPrHistory({ repo: profile.root, mode: options.prHistory ?? "off", consented: options.prHistoryConsented, interactive: options.interactive, dryRun: options.dryRun });
  const files = await renderWithSynthesis(profile, options.wikiSplit, options.synthesis, history.cache);
  validateWikiFiles(profile, files);
  const applied = await applyWikiFiles(profile.root, files, options.dryRun, "init");
  const findings = history.status === "COLLECTED" ? applied.findings : history.reason ? [...applied.findings, { code: "PR_HISTORY_SKIPPED", page: "review-practices.md", detail: history.reason }] : applied.findings;
  return { status: options.dryRun ? "DRY RUN" : "WIKI INITIALIZED", files: files.map((file) => file.path), findings, profile };
}

export async function reinitWiki(options: WikiInitOptions): Promise<WikiResult> {
  const profile = await inventoryRepository(options.repo);
  const history = await collectPrHistory({ repo: profile.root, mode: options.prHistory ?? "off", consented: options.prHistoryConsented, interactive: options.interactive, dryRun: options.dryRun });
  const files = await renderWithSynthesis(profile, options.wikiSplit, options.synthesis, history.cache);
  validateWikiFiles(profile, files);
  const applied = await applyWikiFiles(profile.root, files, options.dryRun, "reinit");
  const findings = history.status === "COLLECTED" ? applied.findings : history.reason ? [...applied.findings, { code: "PR_HISTORY_SKIPPED", page: "review-practices.md", detail: history.reason }] : applied.findings;
  return { status: options.dryRun ? "DRY RUN" : "WIKI REINITIALIZED", files: files.map((file) => file.path), findings, profile };
}

async function renderWithSynthesis(profile: RepositoryProfile, split: WikiSplit, synthesisPath?: string, history?: PrHistoryCache): Promise<WikiFile[]> {
  const files = renderWiki(profile, split);
  if (!synthesisPath) return files;
  const inputPath = await resolveExistingContainedPath(profile.root, synthesisPath, "repository root");
  const synthesis = JSON.parse(await readFile(inputPath, "utf8")) as WikiSynthesis;
  await applyArchitectSynthesis(profile, files, synthesis, history);
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

async function applyArchitectSynthesis(profile: RepositoryProfile, files: WikiFile[], synthesis: WikiSynthesis, collectedHistory?: PrHistoryCache): Promise<void> {
  if (synthesis?.schemaVersion !== 1 || !Array.isArray(synthesis.pages)) throw new Error("Architect synthesis must use schemaVersion 1 and a pages array");
  const tracked = new Set(profile.meaningfulFiles);
  const history = collectedHistory ?? await loadPrHistoryCache(profile.root);
  const seenPages = new Set<string>();
  for (const page of synthesis.pages) {
    if (!page || typeof page.page !== "string" || !Array.isArray(page.sections) || !page.sections.length) throw new Error("Each architect synthesis page needs a page and non-empty sections");
    const relativePage = normalize(page.page.replace(/^\.wiki\//, ""));
    if (!/^(?:[a-z][a-z0-9-]*\/)*[a-z][a-z0-9-]*\.md$/.test(relativePage)) throw new Error(`Invalid architect synthesis page: ${page.page}`);
    if (seenPages.has(relativePage)) throw new Error(`Duplicate architect synthesis page: ${relativePage}`);
    seenPages.add(relativePage);
    const outputPath = `.wiki/${relativePage}`;
    if (relativePage === "review-practices.md" && !history) throw new Error("Review practices require a collected PR-history cache from this wiki init/reinit");
    let file = files.find((candidate) => normalize(candidate.path) === outputPath);
    if (!file) {
      const body = `${wikiOwnershipHeader(outputPath)}\n# ${title(path.posix.basename(relativePage, ".md"))}\n\n${MANAGED_END}\n`;
      file = { path: outputPath, content: body, sourcePaths: [] };
      files.push(file);
    }
    const renderedSections: string[] = [];
    for (const section of page.sections) {
      if (!section || typeof section.heading !== "string" || !/^[A-Z0-9][^\r\n]{2,100}$/i.test(section.heading) || typeof section.body !== "string" || section.body.trim().length < 20 || section.body.length > 6000 || !Array.isArray(section.evidence) || !section.evidence.length) {
        throw new Error(`Invalid architect synthesis section in ${relativePage}`);
      }
      const evidenceLabels: string[] = [];
      for (const evidence of section.evidence) {
        const evidencePath = normalize(evidence.path);
        if (!tracked.has(evidencePath)) throw new Error(`Architect synthesis evidence is not tracked source: ${evidencePath}`);
        const source = await readFile(path.join(profile.root, evidencePath), "utf8");
        const symbols = evidence.symbols ?? [];
        for (const symbol of symbols) {
          if (!symbol || symbol.length > 160 || !source.includes(symbol)) throw new Error(`Architect synthesis symbol not found in ${evidencePath}: ${symbol}`);
        }
        file.sourcePaths.push(evidencePath);
        evidenceLabels.push(symbols.length ? symbols.map((symbol) => `\`${evidencePath}#${symbol}\``).join(", ") : `\`${evidencePath}\``);
      }
      const reviewEvidence = section.reviewEvidence ?? [];
      if (relativePage === "review-practices.md") {
        if (!reviewEvidence.length) throw new Error("Review-practice sections require historical review evidence");
        validateReviewLesson(reviewEvidence, history!);
        evidenceLabels.push(...reviewEvidence.map((evidence) => `${evidence.provider === "github" ? "GitHub" : "Azure"} PR #${evidence.pullRequest}, thread ${evidence.threadId}`));
      } else if (reviewEvidence.length) {
        throw new Error("Historical review evidence is allowed only in review-practices.md");
      }
      renderedSections.push(`## ${section.heading.trim()}\n\n${section.body.trim()}\n\nEvidence: ${evidenceLabels.join(", ")}`);
    }
    const markerIndex = file.content.indexOf(MANAGED_END);
    if (markerIndex < 0) throw new Error(`Managed boundary missing from ${outputPath}`);
    file.content = `${file.content.slice(0, markerIndex).trimEnd()}\n\n${renderedSections.join("\n\n")}\n\n${file.content.slice(markerIndex)}`;
    file.sourcePaths = [...new Set(file.sourcePaths)];
  }
  const practices = files.find((file) => normalize(file.path) === ".wiki/review-practices.md");
  if (practices && practices.content.length > 20_000) throw new Error("review-practices.md exceeds the 20,000-character knowledge budget");
  const index = files.find((file) => normalize(file.path) === ".wiki/index.md");
  if (!index) throw new Error("Generated wiki index is missing");
  const unrouted = synthesis.pages
    .map((page) => normalize(page.page.replace(/^\.wiki\//, "")))
    .filter((page) => page !== "index.md" && !index.content.includes(`](${page})`));
  if (unrouted.length) {
    const rows = unrouted.map((page) => `| ${path.posix.basename(page, ".md").replaceAll("-", ", ")} | [${page}](${page}) | Reviewed architect synthesis | cited tracked evidence |`).join("\n");
    index.content = index.content.replace(/\n(\n## (?:Workspaces|Wiki maintenance))/, `\n${rows}\n$1`);
  }
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
    ["setup, scripts, conventions", "engineering.md", "How to work and verify", "manifests, CI, configs"],
    ["file ownership, entry point", "repository-map.md", "Where code and tests live", "repository tree"],
    ["boundaries, runtime, flow", "architecture.md", "How major parts interact", "manifests, entry points, workspaces"],
    ...optional.map((name) => [name.replace("-", ", "), `${name}.md`, `${title(name)} conventions and boundaries`, sourceScopeFor(name)]),
  ];
  if (profile.signals.has("testing")) routeRows.push(["tests, fixtures, verification", "testing.md", "Testing surfaces", profile.testRoots.join(", ")]);
  const workspaceLinks = workspacePages
    ? profile.workspaces.map((workspace) => `- [${workspace.name}](workspaces/${slug(workspace.name)}.md) — \`${workspace.path}\``)
    : split === "nested" && profile.workspaces.length > 1
      ? profile.workspaces.map((workspace) => `- [${workspace.name}](../${workspace.path}/.wiki/index.md) — closest wiki owns local guidance`)
      : [];
  const index = `${WIKI_MARKER}\n# Repository Wiki\n\nCurrent source code and executable behavior are authoritative.\nRead only the pages relevant to the current task.\n\n## Repository shape\n\n${shapeSummary(profile)}\n\n## Route by task\n\n| Task signals | Read | Answers | Source scope |\n|---|---|---|---|\n${routeRows.map((row) => `| ${row[0]} | [${row[1]}](${row[1]}) | ${row[2]} | ${row[3] || "tracked source"} |`).join("\n")}\n${workspaceLinks.length ? `\n## Workspaces\n\n${workspaceLinks.join("\n")}\n` : ""}\n## Wiki maintenance\n\nRefresh generated knowledge only through \`wiki reinit\` using reviewed, evidence-backed synthesis. Do not add task history or session notes.\n`;
  const topRows = topLevelRows(profile).map((row) => `| \`${row.path}\` | ${row.purpose} | \`${row.start}\` | ${row.tests ? `\`${row.tests}\`` : "—"} |`).join("\n");
  const repositoryMap = `${WIKI_MARKER}\n# Repository Map\n\n## Top-level shape\n\n| Path | Purpose | Start here | Nearest tests |\n|---|---|---|---|\n${topRows || "| `.` | Repository root | `.` | — |"}\n\n## Runtime and product entry points\n\n${bulletPaths(profile.entryPoints)}\n\n## Major ownership boundaries\n\n${profile.workspaces.length ? profile.workspaces.map((item) => `- \`${item.path}\` — independently manifested workspace`).join("\n") : "- The repository has one primary build root."}\n\n## Generated, vendored, and build output\n\n${profile.excludedRoots.length ? profile.excludedRoots.map((item) => `- \`${item}/\` — do not edit as source`).join("\n") : "- No tracked generated or vendored roots were detected."}\n\n## Tests and fixtures\n\n${bulletPaths(profile.testRoots)}\n`;
  const engineering = `${WIKI_MARKER}\n# Engineering Guide\n\n## Verified commands\n\n| Purpose | Command | Scope or notes |\n|---|---|---|\n${profile.commands.length ? profile.commands.map((item) => `| ${item.purpose} | \`${escapeTable(item.command)}\` | ${item.cwd === "." ? "Repository root" : `Targets \`${item.cwd}\` from repository root`}; grounded in \`${item.source}\` |`).join("\n") : "| Repository inspection | `git status --short` | Git-native baseline |"}\n\n## Environment and configuration\n\n- Manifests: ${inlinePaths(profile.manifests)}\n- CI: ${inlinePaths(profile.ciFiles)}\n\n## Testing conventions\n\n- Test roots: ${inlinePaths(profile.testRoots)}\n\n## Verification selection\n\n| Change type | Fast checks | Final evidence |\n|---|---|---|\n| Pure logic | nearest targeted test | affected test suite and build |\n| Documentation | link and path validation | wiki audit |\n`;
  const files: WikiFile[] = [
    { path: ".wiki/index.md", content: index, sourcePaths: profile.manifests.concat(profile.ciFiles) },
    { path: ".wiki/repository-map.md", content: repositoryMap, sourcePaths: profile.entryPoints.concat(profile.testRoots) },
    renderOptionalPage(profile, "architecture"),
    { path: ".wiki/engineering.md", content: engineering, sourcePaths: profile.manifests.concat(profile.ciFiles) },
  ];
  for (const page of optional) files.push(renderOptionalPage(profile, page));
  if (profile.signals.has("testing")) files.push(renderTestingPage(profile));
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
    const lines = file.content.split("\n").length;
    const budget = normalizedPath.endsWith("index.md") ? 100 : normalizedPath.endsWith("repository-map.md") || normalizedPath.endsWith("engineering.md") ? 220 : 160;
    if (lines > budget) throw new Error(`Wiki page exceeds ${budget}-line budget: ${normalizedPath}`);
  }
  const generated = files.map((file) => ({ path: file.path, content: file.content, sourceId: `wiki:${file.path}` }));
  const broken = findBrokenLinks(generated);
  if (broken.length) throw new Error(`Broken generated wiki links:\n${broken.join("\n")}`);
  for (const command of profile.commands) {
    if (!tracked.has(command.source)) throw new Error(`Ungrounded command ${command.command}: ${command.source}`);
  }
}

async function applyWikiFiles(repoRoot: string, files: WikiFile[], dryRun: boolean, mode: "init" | "reinit"): Promise<ApplyWikiResult> {
  const previous = await loadWikiInventory(repoRoot);
  const previousByPath = new Map(previous.files.map((item) => [item.path, item]));
  const conflicts: string[] = [];
  const mergedFiles: WikiFile[] = [];
  const backups: Array<{ path: string; content: string }> = [];
  const staleRemovals: Array<{ path: string; content: string }> = [];
  const findings: WikiFinding[] = [];
  for (const file of files) {
    const normalizedPath = normalize(file.path);
    try {
      const existingPath = await resolveExistingContainedPath(repoRoot, normalizedPath, "repository root");
      const existing = await readFile(existingPath, "utf8");
      const prior = previousByPath.get(normalizedPath);
      if (prior) {
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
  if (mode === "reinit") {
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
  if (dryRun) return { findings };
  if (mode === "reinit") {
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    for (const backup of backups.concat(staleRemovals)) await atomicWriteContained(repoRoot, `.git/agentic-kit/wiki-backups/${stamp}/${backup.path.replaceAll("/", "__")}`, backup.content, "repository root");
    for (const stale of staleRemovals) await unlinkContained(repoRoot, stale.path, "repository root");
  }
  for (const file of mergedFiles) await atomicWriteContained(repoRoot, file.path, file.content, "repository root");
  const merged = new Map(previous.files.map((item) => [item.path, item]));
  for (const stale of staleRemovals) merged.delete(stale.path);
  for (const file of mergedFiles) merged.set(normalize(file.path), { path: normalize(file.path), sourceId: wikiSourceId(normalize(file.path)), sha256: sha256(file.content) });
  const inventory: WikiInventory = { schemaVersion: 1, files: [...merged.values()].sort((a, b) => a.path.localeCompare(b.path)) };
  await atomicWriteContained(repoRoot, WIKI_INVENTORY, `${JSON.stringify(inventory, null, 2)}\n`, "repository root");
  return { findings };
}

async function loadWikiInventory(repoRoot: string): Promise<WikiInventory> {
  try {
    const inventoryPath = await resolveExistingContainedPath(repoRoot, WIKI_INVENTORY, "repository root");
    const value = JSON.parse(await readFile(inventoryPath, "utf8")) as WikiInventory;
    if (value.schemaVersion !== 1 || !Array.isArray(value.files) || value.files.some((item) => !item || typeof item.path !== "string" || item.sourceId !== wikiSourceId(item.path) || !/^[a-f0-9]{64}$/.test(item.sha256))) throw new Error("wiki ownership inventory invalid");
    return value;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { schemaVersion: 1, files: [] };
    throw error;
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
  const wikiRoot = path.join(profile.root, ".wiki");
  let names: string[];
  try {
    names = (await readdir(wikiRoot, { recursive: true, withFileTypes: true })).filter((entry) => entry.isFile() && entry.name.endsWith(".md")).map((entry) => normalize(path.relative(wikiRoot, path.join(entry.parentPath, entry.name))));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return ["index.md", "repository-map.md", "architecture.md", "engineering.md"].map((page) => ({ code: "MISSING_REQUIRED_PAGE", page, detail: `.wiki/${page} does not exist` }));
    throw error;
  }
  const contents = new Map<string, string>();
  for (const name of names) contents.set(name, await readFile(path.join(wikiRoot, name), "utf8"));
  const findings: WikiFinding[] = [];
  for (const required of ["index.md", "repository-map.md", "architecture.md", "engineering.md"]) {
    if (!contents.has(required)) findings.push({ code: "MISSING_REQUIRED_PAGE", page: required, detail: `Required wiki page ${required} is missing` });
  }
  const generated = [...contents].map(([page, content]) => ({ path: `.wiki/${page}`, content, sourceId: `wiki:${page}` }));
  for (const broken of findBrokenLinks(generated)) {
    const [source, target] = broken.split(" -> ");
    const page = source!.replace(/^\.wiki\//, "");
    const line = lineContaining(contents.get(page)!, target!);
    findings.push({ code: "BROKEN_LINK", page, detail: target!, line });
  }
  const index = contents.get("index.md") ?? "";
  for (const page of names.filter((name) => name !== "index.md" && !name.startsWith("workspaces/"))) {
    if (!index.includes(page)) findings.push({ code: "UNINDEXED_PAGE", page, detail: "Page is not routed by index.md" });
  }
  const seen = new Map<string, string>();
  for (const [page, content] of contents) {
    const lines = content.split(/\r?\n/);
    const budget = page === "index.md" ? 100 : page === "repository-map.md" || page === "architecture.md" || page === "engineering.md" ? 220 : 160;
    if (lines.length > budget) findings.push({ code: "OVERSIZED_PAGE", page, detail: `${lines.length} lines exceeds ${budget}` });
    lines.forEach((line, indexNumber) => {
      for (const match of line.matchAll(/`([^`]+[\/][^`]*)`/g)) {
        const candidate = normalize(match[1]!);
        if (/[*?\[\]]/.test(candidate) || candidate.startsWith("http")) continue;
        const candidatePath = candidate.split("#", 1)[0]!;
        if (!profile.trackedFiles.includes(candidatePath) && !candidate.startsWith("npm ") && !candidate.startsWith("python ")) findings.push({ code: "MISSING_PATH", page, detail: candidate, line: indexNumber + 1 });
      }
      const normalizedLine = line.trim().toLowerCase();
      if (normalizedLine.length > 35 && !normalizedLine.startsWith("|") && !normalizedLine.startsWith("<!--")) {
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

function renderOptionalPage(profile: RepositoryProfile, page: string): WikiFile {
  if (page === "architecture") {
    const sources = [...new Set(profile.workspaces.map((item) => item.manifest).concat(profile.manifests, profile.entryPoints))].slice(0, 40);
    const body = `${WIKI_MARKER}\n# Architecture\n\n## Workspace boundaries\n\n${profile.workspaces.map((item) => `- \`${item.path}\` is independently manifested by \`${item.manifest}\`.`).join("\n")}\n\n## Runtime entry points\n\n${bulletPaths(profile.entryPoints)}\n\n## Verification\n\n${profile.workspaces.flatMap((item) => item.commands).map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- Workspace manifests are the current boundary evidence."}\n`;
    return { path: ".wiki/architecture.md", content: serializeFrontmatter({ use_when: ["architecture", "workspace", "boundary"], source_paths: sources }, body), sourcePaths: sources };
  }
  const area = profile.areas[page]!;
  const sourcePaths = [...new Set(area.sources.concat(area.tests, area.commands.map((item) => item.source)))];
  const body = `${WIKI_MARKER}\n# ${title(page)}\n\n## Ownership roots\n\n${bulletPaths(area.roots)}\n\n## Entry points and flow evidence\n\n${bulletPaths(area.sources)}\n\n## Tests\n\n${bulletPaths(area.tests)}\n\n## Verified commands\n\n${area.commands.map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- Area verification is grounded by the listed tracked tests."}\n`;
  return { path: `.wiki/${page}.md`, content: serializeFrontmatter({ use_when: page.split("-"), source_paths: sourcePaths }, body), sourcePaths };
}

function renderTestingPage(profile: RepositoryProfile): WikiFile {
  const sources = profile.testRoots;
  const body = `${WIKI_MARKER}\n# Testing\n\n## Test locations\n\n${bulletPaths(sources)}\n\n## Verified commands\n\n${profile.commands.filter((item) => /test|e2e/i.test(item.purpose)).map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- No test command was deterministically grounded; inspect maintained CI before running one."}\n`;
  return { path: ".wiki/testing.md", content: serializeFrontmatter({ use_when: ["test", "fixture", "e2e"], source_paths: sources }, body), sourcePaths: sources };
}

function renderWorkspacePage(workspace: WorkspaceProfile): WikiFile {
  const body = `${WIKI_MARKER}\n# ${workspace.name} Workspace\n\n## Purpose and boundary\n\n\`${workspace.path}\` is independently manifested by \`${workspace.manifest}\`.\n\n## Verified commands\n\n${workspace.commands.map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- No workspace-local command was grounded."}\n`;
  return { path: `.wiki/workspaces/${slug(workspace.name)}.md`, content: serializeFrontmatter({ use_when: [workspace.name], source_paths: [workspace.manifest] }, body), sourcePaths: [workspace.manifest] };
}

function renderNestedWorkspaceWiki(workspace: WorkspaceProfile): WikiFile[] {
  const prefix = `${workspace.path}/.wiki`;
  const index = `${WIKI_MARKER}\n# ${workspace.name} Wiki\n\nCurrent source is authoritative.\n\n- [Repository map](repository-map.md)\n- [Engineering](engineering.md)\n`;
  const map = `${WIKI_MARKER}\n# Repository Map\n\n## Workspace root\n\n- \`${workspace.path}\`\n- Manifest: \`${workspace.manifest}\`\n`;
  const engineering = `${WIKI_MARKER}\n# Engineering Guide\n\n## Verified commands\n\n${workspace.commands.map((item) => `- \`${item.command}\` — \`${item.source}\``).join("\n") || "- No workspace-local command was grounded."}\n`;
  return [
    { path: `${prefix}/index.md`, content: index, sourcePaths: [workspace.manifest] },
    { path: `${prefix}/repository-map.md`, content: map, sourcePaths: [workspace.manifest] },
    { path: `${prefix}/engineering.md`, content: engineering, sourcePaths: [workspace.manifest] },
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
  return content.replace(/\r\n/g, "\n").split("\n").some((line) => line === expected);
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
