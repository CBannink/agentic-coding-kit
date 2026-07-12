import { cp, mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { installHost, type InstallOptions, type InstallResult } from "./install.js";
import { resolveProjectRoot } from "./host-paths.js";

export interface MigrationResult { backupRoot: string; candidates: string[]; install: InstallResult }

export async function migrateLegacy(options: InstallOptions): Promise<MigrationResult> {
  if (options.scope !== "project") return { backupRoot: "NONE", candidates: [], install: await installHost(options) };
  const repo = await resolveProjectRoot(options.repo ?? process.cwd());
  const candidates: string[] = [];
  for (const candidate of [".kit", ".wiki/.features", ".agents/session-state"]) {
    try { await readFile(path.join(repo, candidate)); candidates.push(candidate); }
    catch (error) {
      const { stat } = await import("node:fs/promises");
      try { await stat(path.join(repo, candidate)); candidates.push(candidate); } catch { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
    }
  }
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupRoot = path.join(repo, ".agentic-kit-backup", stamp);
  if (!options.dryRun && candidates.length) {
    await mkdir(backupRoot, { recursive: true });
    for (const candidate of candidates) await cp(path.join(repo, candidate), path.join(backupRoot, candidate), { recursive: true, force: false });
    const ignore = path.join(repo, ".gitignore");
    let content = ""; try { content = await readFile(ignore, "utf8"); } catch { /* new */ }
    if (!content.split(/\r?\n/).includes(".agentic-kit-backup/")) await writeFile(ignore, `${content.trimEnd()}${content.trim() ? "\n" : ""}.agentic-kit-backup/\n`, "utf8");
  }
  return { backupRoot, candidates, install: await installHost(options) };
}
