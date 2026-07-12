import { execFile as execFileCallback } from "node:child_process";
import { promisify } from "node:util";
import { createInterface } from "node:readline/promises";
import { atomicWriteContained } from "./paths.js";

const execFile = promisify(execFileCallback);
export const PR_HISTORY_LOOKBACK_DAYS = 120;
export const PR_HISTORY_MAX_PRS = 100;
export const PR_HISTORY_MAX_THREADS = 1000;
export type PrHistoryMode = "auto" | "on" | "off";
export type PrProvider = "github" | "azure";

export interface PrRemote { provider: PrProvider; host: string; owner?: string; repository: string; organization?: string; project?: string }
export interface CommandResult { stdout: string; stderr?: string; exitCode: number }
export type CommandRunner = (command: string, args: string[], cwd: string) => Promise<CommandResult>;
export interface NormalizedReviewThread {
  provider: PrProvider;
  pullRequest: number;
  threadId: string;
  url?: string;
  path?: string;
  author?: string;
  body: string;
  createdAt: string;
  reviewState?: string;
  resolved: boolean;
  codeChangedAfter: boolean;
}
export interface PrHistoryCache { schemaVersion: 1; collectedAt: string; lookbackDays: number; provider: PrProvider; remote: Omit<PrRemote, "host"> & { host: string }; threads: NormalizedReviewThread[] }
export interface CollectPrHistoryOptions { repo: string; mode: PrHistoryMode; consented?: boolean; interactive?: boolean; confirm?: (message: string) => Promise<boolean>; now?: Date; runner?: CommandRunner; dryRun?: boolean }
export interface CollectPrHistoryResult { status: "COLLECTED" | "SKIPPED" | "UNAVAILABLE"; reason?: string; cachePath?: string; cache?: PrHistoryCache }

export function detectPrRemote(remotes: string[]): PrRemote | undefined {
  for (const raw of remotes) {
    const value = raw.trim();
    let match = value.match(/(?:https?:\/\/|git@)([^/:]+)[/:]([^/]+)\/([^/]+?)(?:\.git)?$/i);
    if (match && !/dev\.azure|visualstudio/i.test(match[1]!)) {
      return { provider: "github", host: match[1]!, owner: match[2]!, repository: match[3]!.replace(/\.git$/i, "") };
    }
    match = value.match(/(?:https:\/\/|git@ssh\.)dev\.azure\.com[/:]v3\/([^/]+)\/([^/]+)\/([^/]+?)(?:\.git)?$/i)
      ?? value.match(/https:\/\/([^@/]+@)?dev\.azure\.com\/([^/]+)\/([^/]+)\/_git\/([^/]+)/i);
    if (match) {
      const groups = match.length === 4 ? [match[1], match[2], match[3]] : [match[2], match[3], match[4]];
      return { provider: "azure", host: "dev.azure.com", organization: groups[0]!, project: groups[1]!, repository: groups[2]!.replace(/\.git$/i, "") };
    }
    match = value.match(/https:\/\/([^.]+)\.visualstudio\.com\/([^/]+)\/_git\/([^/]+)/i);
    if (match) return { provider: "azure", host: `${match[1]}.visualstudio.com`, organization: match[1]!, project: match[2]!, repository: match[3]!.replace(/\.git$/i, "") };
  }
  return undefined;
}

export async function collectPrHistory(options: CollectPrHistoryOptions): Promise<CollectPrHistoryResult> {
  if (options.mode === "off") return { status: "SKIPPED", reason: "PR history disabled" };
  if (options.mode === "auto" && !options.consented && !options.interactive) return { status: "SKIPPED", reason: "Non-interactive auto mode does not read private PR history" };
  const runner = options.runner ?? defaultRunner;
  const remotes = await runner("git", ["remote", "get-url", "--all", "origin"], options.repo);
  const remote = detectPrRemote(remotes.stdout.split(/\r?\n/).filter(Boolean));
  if (!remote) return unavailable(options.mode, "No supported GitHub or Azure DevOps origin remote found");
  if (options.mode === "auto" && !options.consented) {
    if (!options.interactive) return { status: "SKIPPED", reason: "Non-interactive auto mode does not read private PR history" };
    const available = await providerAvailable(options.repo, remote, runner);
    if (!available) return { status: "UNAVAILABLE", reason: `${remote.provider === "github" ? "GitHub" : "Azure DevOps"} CLI is unavailable or not authenticated` };
    const confirm = options.confirm ?? terminalConfirm;
    if (!await confirm(`Read up to ${PR_HISTORY_MAX_PRS} merged PRs and ${PR_HISTORY_MAX_THREADS} human review threads from the previous ${PR_HISTORY_LOOKBACK_DAYS} days using existing ${remote.provider === "github" ? "gh" : "az"} authentication?`)) {
      return { status: "SKIPPED", reason: "PR-history consent declined" };
    }
  }
  const now = options.now ?? new Date();
  const cutoff = new Date(now.getTime() - PR_HISTORY_LOOKBACK_DAYS * 86_400_000).toISOString();
  let threads: NormalizedReviewThread[];
  try {
    threads = remote.provider === "github"
      ? await collectGithub(options.repo, remote, cutoff, runner)
      : await collectAzure(options.repo, remote, cutoff, runner);
  } catch (error) {
    return unavailable(options.mode, error instanceof Error ? error.message : String(error));
  }
  threads = threads.filter((thread) => thread.body.trim() && !isBot(thread.author)).slice(0, PR_HISTORY_MAX_THREADS);
  const cache: PrHistoryCache = { schemaVersion: 1, collectedAt: now.toISOString(), lookbackDays: PR_HISTORY_LOOKBACK_DAYS, provider: remote.provider, remote, threads };
  const cachePath = ".git/agentic-kit/pr-history/history.json";
  if (!options.dryRun) await atomicWriteContained(options.repo, cachePath, `${JSON.stringify(cache, null, 2)}\n`, "repository");
  return { status: "COLLECTED", cachePath, cache };
}

async function collectGithub(cwd: string, remote: PrRemote, cutoff: string, run: CommandRunner): Promise<NormalizedReviewThread[]> {
  const auth = await run("gh", ["auth", "status", "--hostname", remote.host], cwd);
  if (auth.exitCode !== 0) throw new Error("GitHub CLI is unavailable or not authenticated");
  const repo = `${remote.owner}/${remote.repository}`;
  const pulls = parseArray(await runOrThrow(run, "gh", ["api", "--method", "GET", `repos/${repo}/pulls`, "-f", "state=closed", "-f", "sort=updated", "-f", "direction=desc", "-f", "per_page=100"], cwd));
  const merged = pulls.filter((pr) => pr.merged_at && String(pr.merged_at) >= cutoff).slice(0, PR_HISTORY_MAX_PRS);
  const out: NormalizedReviewThread[] = [];
  for (const pr of merged) {
    const number = Number(pr.number);
    const [reviews, comments, commits] = await Promise.all([
      runOrThrow(run, "gh", ["api", "--method", "GET", "--paginate", "--slurp", `repos/${repo}/pulls/${number}/reviews`, "-f", "per_page=100"], cwd),
      runOrThrow(run, "gh", ["api", "--method", "GET", "--paginate", "--slurp", `repos/${repo}/pulls/${number}/comments`, "-f", "per_page=100"], cwd),
      runOrThrow(run, "gh", ["api", "--method", "GET", "--paginate", "--slurp", `repos/${repo}/pulls/${number}/commits`, "-f", "per_page=100"], cwd),
    ]);
    const states = new Map(parsePagedArray(reviews).map((review) => [String(review.user?.login ?? ""), String(review.state ?? "")]));
    const commitDates = parsePagedArray(commits).map((commit) => String(commit.commit?.author?.date ?? commit.commit?.committer?.date ?? "")).filter(Boolean);
    for (const comment of parsePagedArray(comments)) {
      if (comment.deleted_at) continue;
      const author = String(comment.user?.login ?? "");
      const createdAt = String(comment.created_at ?? "");
      out.push({ provider: "github", pullRequest: number, threadId: String(comment.id), url: stringOrUndefined(comment.html_url), path: stringOrUndefined(comment.path), author, body: String(comment.body ?? ""), createdAt, reviewState: states.get(author), resolved: comment.resolved === true, codeChangedAfter: Boolean(createdAt && commitDates.some((date) => date > createdAt)) });
    }
  }
  return out;
}

async function collectAzure(cwd: string, remote: PrRemote, cutoff: string, run: CommandRunner): Promise<NormalizedReviewThread[]> {
  const extension = await run("az", ["extension", "show", "--name", "azure-devops", "--output", "json"], cwd);
  if (extension.exitCode !== 0) throw new Error("Azure CLI DevOps extension is unavailable");
  const organization = `https://dev.azure.com/${remote.organization}`;
  const pulls = parseArray(await runOrThrow(run, "az", ["repos", "pr", "list", "--status", "completed", "--repository", remote.repository, "--organization", organization, "--project", remote.project!, "--top", String(PR_HISTORY_MAX_PRS), "--output", "json"], cwd));
  const merged = pulls.filter((pr) => String(pr.closedDate ?? pr.creationDate ?? "") >= cutoff).slice(0, PR_HISTORY_MAX_PRS);
  const out: NormalizedReviewThread[] = [];
  for (const pr of merged) {
    const number = Number(pr.pullRequestId);
    const response = parseObject(await runOrThrow(run, "az", ["devops", "invoke", "--area", "git", "--resource", "pullRequestThreads", "--route-parameters", `project=${remote.project}`, `repositoryId=${remote.repository}`, `pullRequestId=${number}`, "--organization", organization, "--api-version", "7.1", "--output", "json"], cwd));
    for (const thread of arrayValue(response.value)) for (const comment of arrayValue(thread.comments)) {
      if (comment.isDeleted || Number(comment.commentType) === 3) continue;
      out.push({ provider: "azure", pullRequest: number, threadId: String(thread.id), path: stringOrUndefined(thread.threadContext?.filePath), author: stringOrUndefined(comment.author?.displayName), body: String(comment.content ?? ""), createdAt: String(comment.publishedDate ?? ""), reviewState: String(thread.status ?? ""), resolved: /^fixed$/i.test(String(thread.status ?? "")), codeChangedAfter: false });
    }
  }
  return out;
}

async function runOrThrow(run: CommandRunner, command: string, args: string[], cwd: string): Promise<string> {
  const result = await run(command, args, cwd);
  if (result.exitCode !== 0) throw new Error(`${command} command failed: ${result.stderr || "unknown error"}`);
  return result.stdout;
}

const defaultRunner: CommandRunner = async (command, args, cwd) => {
  try {
    const result = await execFile(command, args, { cwd, encoding: "utf8", maxBuffer: 20 * 1024 * 1024 });
    return { stdout: result.stdout, stderr: result.stderr, exitCode: 0 };
  } catch (error) {
    const value = error as Error & { stdout?: string; stderr?: string; code?: number };
    return { stdout: value.stdout ?? "", stderr: value.stderr ?? value.message, exitCode: typeof value.code === "number" ? value.code : 1 };
  }
};

async function providerAvailable(cwd: string, remote: PrRemote, run: CommandRunner): Promise<boolean> {
  if (remote.provider === "github") return (await run("gh", ["auth", "status", "--hostname", remote.host], cwd)).exitCode === 0;
  return (await run("az", ["extension", "show", "--name", "azure-devops", "--output", "json"], cwd)).exitCode === 0;
}

async function terminalConfirm(message: string): Promise<boolean> {
  const terminal = createInterface({ input: process.stdin, output: process.stdout });
  try { return /^y(?:es)?$/i.test((await terminal.question(`${message} [y/N] `)).trim()); }
  finally { terminal.close(); }
}

function unavailable(mode: PrHistoryMode, reason: string): CollectPrHistoryResult {
  if (mode === "on") throw new Error(reason);
  return { status: "UNAVAILABLE", reason };
}
function isBot(author?: string): boolean { return Boolean(author && (/\[bot\]$/i.test(author) || /(^|[-_ ])bot$/i.test(author))); }
function parseArray(text: string): any[] { const value: unknown = JSON.parse(text || "[]"); return Array.isArray(value) ? value : []; }
function parsePagedArray(text: string): any[] {
  const value = parseArray(text);
  return value.length > 0 && value.every(Array.isArray) ? value.flat() : value;
}
function parseObject(text: string): any { const value: unknown = JSON.parse(text || "{}"); return value && typeof value === "object" ? value : {}; }
function arrayValue(value: unknown): any[] { return Array.isArray(value) ? value : []; }
function stringOrUndefined(value: unknown): string | undefined { return typeof value === "string" && value ? value : undefined; }
