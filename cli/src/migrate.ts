import { cp, lstat, mkdir, readFile } from "node:fs/promises";
import path from "node:path";
import { installHost, type InstallOptions, type InstallResult } from "./install.js";
import { resolveProjectRoot } from "./host-paths.js";
import { atomicWriteContained, resolveContainedPath, resolveExistingContainedPath } from "./paths.js";

export interface MigrationResult { backupRoot: string; candidates: string[]; install: InstallResult }

export async function migrateLegacy(options: InstallOptions): Promise<MigrationResult> {
  if (options.scope !== "project") return { backupRoot: "NONE", candidates: [], install: await installHost(options) };
  const repo = await resolveProjectRoot(options.repo ?? process.cwd());
  const candidates: string[] = [];
  for (const candidate of [".kit", ".wiki/.features", ".agents/session-state"]) {
    const target = resolveContainedPath(repo, candidate, "legacy migration source");
    try {
      const state = await lstat(target);
      if (state.isSymbolicLink()) throw new Error(`Refusing linked legacy migration source: ${target}`);
      await resolveExistingContainedPath(repo, candidate, "legacy migration source");
      candidates.push(candidate);
    } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupParent = resolveContainedPath(repo, ".agentic-kit-backup", "migration backup");
  const backupRoot = resolveContainedPath(backupParent, stamp, "migration backup");
  if (!options.dryRun && candidates.length) {
    try {
      const state = await lstat(backupParent);
      if (state.isSymbolicLink() || !state.isDirectory()) throw new Error(`Unsafe migration backup root: ${backupParent}`);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      await mkdir(backupParent);
    }
    await mkdir(backupRoot);
    for (const candidate of candidates) {
      const source = resolveContainedPath(repo, candidate, "legacy migration source");
      const destination = resolveContainedPath(backupRoot, candidate, "migration backup");
      await cp(source, destination, {
        recursive: true,
        force: false,
        errorOnExist: true,
        filter: async (entry) => {
          if ((await lstat(entry)).isSymbolicLink()) throw new Error(`Refusing linked legacy migration entry: ${entry}`);
          return true;
        },
      });
    }
    const ignore = resolveContainedPath(repo, ".gitignore", "repository");
    let content = "";
    try { content = await readFile(ignore, "utf8"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
    if (!content.split(/\r?\n/).includes(".agentic-kit-backup/")) {
      await atomicWriteContained(repo, ".gitignore", `${content.trimEnd()}${content.trim() ? "\n" : ""}.agentic-kit-backup/\n`, "repository");
    }
  }
  return { backupRoot, candidates, install: await installHost(options) };
}
