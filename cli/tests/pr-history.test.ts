import { execFile as execFileCallback } from "node:child_process";
import { mkdtemp, mkdir, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { describe, expect, it } from "vitest";
import { collectPrHistory, detectPrRemote, type CommandRunner } from "../src/pr-history.js";
import { initWiki } from "../src/wiki.js";

const execFile = promisify(execFileCallback);

describe("PR history", () => {
  it("detects GitHub, GitHub Enterprise, and Azure DevOps remotes", () => {
    expect(detectPrRemote(["git@github.com:acme/widget.git"])).toMatchObject({ provider: "github", owner: "acme", repository: "widget" });
    expect(detectPrRemote(["https://github.company.test/acme/widget.git"])).toMatchObject({ provider: "github", host: "github.company.test" });
    expect(detectPrRemote(["https://dev.azure.com/acme/platform/_git/widget"])).toMatchObject({ provider: "azure", organization: "acme", project: "platform", repository: "widget" });
    expect(detectPrRemote(["git@ssh.dev.azure.com:v3/acme/platform/widget"])).toMatchObject({ provider: "azure", organization: "acme" });
    expect(detectPrRemote(["git@git.company.com:acme/widget.git"])).toMatchObject({ provider: "github", host: "git.company.com" });
  });

  it("requires consent in auto mode and fails clearly when on is unavailable", async () => {
    const runner: CommandRunner = async () => ({ stdout: "", exitCode: 1 });
    await expect(collectPrHistory({ repo: ".", mode: "auto", runner })).resolves.toMatchObject({ status: "SKIPPED" });
    await expect(collectPrHistory({ repo: ".", mode: "on", runner })).rejects.toThrow(/supported GitHub or Azure/i);
  });

  it("collects recent human GitHub review comments into a local cache", async () => {
    const repo = await mkdtemp(path.join(tmpdir(), "kit-pr-history-"));
    const calls: string[] = [];
    const runner: CommandRunner = async (command, args) => {
      calls.push(`${command} ${args.join(" ")}`);
      if (command === "git") return { stdout: "https://github.com/acme/widget.git\n", exitCode: 0 };
      if (args[0] === "auth") return { stdout: "ok", exitCode: 0 };
      if (args.includes("repos/acme/widget/pulls")) return { stdout: JSON.stringify([{ number: 7, merged_at: "2026-06-01T00:00:00Z", merge_commit_sha: "merged" }, { number: 8, merged_at: null }]), exitCode: 0 };
      if (args.some((arg) => arg.endsWith("/reviews"))) return { stdout: JSON.stringify([{ state: "CHANGES_REQUESTED", user: { login: "alice" } }]), exitCode: 0 };
      if (args.some((arg) => arg.endsWith("/commits"))) return { stdout: JSON.stringify([{ commit: { author: { date: "2026-06-03T00:00:00Z" } } }]), exitCode: 0 };
      return { stdout: JSON.stringify([{ id: 10, user: { login: "alice" }, body: "Reuse the shared request helper.", created_at: "2026-06-02T00:00:00Z", path: "src/api.ts", commit_id: "old" }, { id: 11, user: { login: "lint[bot]" }, body: "format", created_at: "2026-06-02T00:00:00Z" }]), exitCode: 0 };
    };
    const result = await collectPrHistory({ repo, mode: "on", consented: true, runner, now: new Date("2026-07-01T00:00:00Z") });
    expect(result.cache?.threads).toHaveLength(1);
    expect(result.cache?.threads[0]).toMatchObject({ pullRequest: 7, reviewState: "CHANGES_REQUESTED", codeChangedAfter: true });
    expect(calls.filter((call) => call.startsWith("gh api")).every((call) => call.includes("--method GET"))).toBe(true);
    expect(calls.filter((call) => /\/(reviews|comments|commits)\b/.test(call)).every((call) => call.includes("--paginate --slurp"))).toBe(true);
    expect(JSON.parse(await readFile(path.join(repo, ".git/agentic-kit/pr-history/history.json"), "utf8"))).not.toHaveProperty("token");
  });

  it("asks in interactive auto mode only after authenticated provider detection", async () => {
    const calls: string[] = [];
    const runner: CommandRunner = async (command, args) => {
      calls.push(`${command} ${args.join(" ")}`);
      if (command === "git") return { stdout: "https://github.com/acme/widget.git\n", exitCode: 0 };
      if (args[0] === "auth") return { stdout: "ok", exitCode: 0 };
      return { stdout: "[]", exitCode: 0 };
    };
    let prompt = "";
    const result = await collectPrHistory({ repo: await mkdtemp(path.join(tmpdir(), "kit-pr-consent-")), mode: "auto", interactive: true, runner, confirm: async (message) => { prompt = message; return false; } });
    expect(result).toMatchObject({ status: "SKIPPED", reason: "PR-history consent declined" });
    expect(calls.some((call) => call.startsWith("gh auth status"))).toBe(true);
    expect(prompt).toContain("120 days");
  });

  it("collects Azure DevOps resolved human threads through native az commands", async () => {
    const repo = await mkdtemp(path.join(tmpdir(), "kit-pr-azure-"));
    const calls: string[] = [];
    const runner: CommandRunner = async (command, args) => {
      calls.push(`${command} ${args.join(" ")}`);
      if (command === "git") return { stdout: "https://dev.azure.com/acme/platform/_git/widget\n", exitCode: 0 };
      if (args[0] === "extension") return { stdout: "{}", exitCode: 0 };
      if (args[0] === "repos") return { stdout: JSON.stringify([{ pullRequestId: 42, closedDate: "2026-06-01T00:00:00Z" }]), exitCode: 0 };
      return { stdout: JSON.stringify({ value: [{ id: 5, status: "fixed", threadContext: { filePath: "src/api.ts" }, pullRequestThreadContext: { changeTrackingId: 2 }, comments: [{ author: { displayName: "Alice" }, content: "Use the shared client.", publishedDate: "2026-06-02T00:00:00Z" }, { author: { displayName: "Bot" }, content: "deleted", isDeleted: true }] }] }), exitCode: 0 };
    };
    const result = await collectPrHistory({ repo, mode: "on", runner, now: new Date("2026-07-01T00:00:00Z") });
    expect(result.cache?.threads).toEqual([expect.objectContaining({ provider: "azure", pullRequest: 42, threadId: "5", resolved: true, codeChangedAfter: false })]);
    expect(calls.some((call) => call.startsWith("az repos pr list"))).toBe(true);
    expect(calls.some((call) => call.startsWith("az devops invoke"))).toBe(true);
  });

  it("writes validated condensed lessons without copying raw comments", async () => {
    const repo = await createGitRepo({ "package.json": JSON.stringify({ name: "reviewed" }), "src/api.ts": "export function sharedRequest() {}\n" });
    const cache = { schemaVersion: 1, collectedAt: "2026-07-01T00:00:00Z", lookbackDays: 120, provider: "github", remote: { provider: "github", host: "github.com", owner: "acme", repository: "reviewed" }, threads: [{ provider: "github", pullRequest: 7, threadId: "10", author: "alice", body: "RAW PRIVATE COMMENT THAT MUST NOT LEAK", createdAt: "2026-06-02", reviewState: "CHANGES_REQUESTED", resolved: true, codeChangedAfter: true }] };
    await mkdir(path.join(repo, ".git/agentic-kit/pr-history"), { recursive: true });
    await writeFile(path.join(repo, ".git/agentic-kit/pr-history/history.json"), JSON.stringify(cache), "utf8");
    const standardPages = ["repository-map.md", "engineering.md", "coding.md", "reviewing.md", "testing.md", "security.md"].map((page) => ({
      page,
      sections: [{ heading: `Reviewed ${page.replace(".md", "")}`, body: `The ${page} guidance is grounded in the current repository manifest and remains subordinate to live source.`, evidence: [{ path: "package.json" }] }],
    }));
    const synthesis = { schemaVersion: 1, pages: [...standardPages, { page: "review-practices.md", sections: [{ heading: "Reuse boundary helpers", body: "API changes reuse the established shared request helper rather than introducing endpoint-local equivalents.", evidence: [{ path: "src/api.ts", symbols: ["sharedRequest"] }], reviewEvidence: [{ provider: "github", pullRequest: 7, threadId: "10" }] }] }] };
    await writeFile(path.join(repo, "synthesis.json"), JSON.stringify(synthesis), "utf8");
    await execFile("git", ["-C", repo, "add", "synthesis.json"]);
    await initWiki({ repo, wikiSplit: "root", dryRun: false, synthesis: "synthesis.json", prHistory: "off" });
    const page = await readFile(path.join(repo, ".wiki/review-practices.md"), "utf8");
    expect(page).toContain("GitHub PR #7, thread 10");
    expect(page).not.toContain("RAW PRIVATE COMMENT");
    expect(page.length).toBeLessThanOrEqual(20_000);
  });
});

async function createGitRepo(files: Record<string, string>): Promise<string> {
  const root = await mkdtemp(path.join(tmpdir(), "kit-pr-wiki-"));
  await execFile("git", ["init", root]);
  await execFile("git", ["-C", root, "config", "user.email", "test@example.com"]);
  await execFile("git", ["-C", root, "config", "user.name", "Test"]);
  for (const [relative, content] of Object.entries(files)) {
    const target = path.join(root, relative);
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, content, "utf8");
  }
  await execFile("git", ["-C", root, "add", "."]);
  await execFile("git", ["-C", root, "commit", "-m", "fixture"]);
  return root;
}
