import { lstat, mkdir, open, realpath, rename, unlink } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";

export type PathOperationStage = "before-final-write-check" | "before-final-delete-check";
export type PathOperationHook = (stage: PathOperationStage, target: string) => void | Promise<void>;

let operationHook: PathOperationHook | undefined;

export function setPathOperationHookForTests(hook?: PathOperationHook): void {
  operationHook = hook;
}

export function resolveContainedPath(root: string, candidate: string, boundaryLabel: string): string {
  if (!candidate || candidate.includes("\0")) throw new Error(`Path must remain inside ${boundaryLabel}`);
  if (path.isAbsolute(candidate) || path.win32.isAbsolute(candidate) || path.posix.isAbsolute(candidate) || /^[a-zA-Z]:/.test(candidate)) {
    throw new Error(`Absolute path escapes ${boundaryLabel}: ${candidate}`);
  }
  const segments = candidate.split(/[\\/]+/);
  if (segments.includes("..")) throw new Error(`Path traversal escapes ${boundaryLabel}: ${candidate}`);
  const resolvedRoot = path.resolve(root);
  const resolvedTarget = path.resolve(resolvedRoot, ...segments.filter((segment) => segment && segment !== "."));
  assertAbsoluteContained(resolvedRoot, resolvedTarget, boundaryLabel);
  return resolvedTarget;
}

export async function resolveExistingContainedPath(root: string, candidate: string, boundaryLabel: string): Promise<string> {
  const lexicalTarget = resolveContainedPath(root, candidate, boundaryLabel);
  await assertSafeAncestry(root, lexicalTarget, boundaryLabel, true);
  const [realRoot, realTarget] = await Promise.all([realpath(path.resolve(root)), realpath(lexicalTarget)]);
  assertAbsoluteContained(realRoot, realTarget, boundaryLabel);
  return lexicalTarget;
}

export async function atomicWriteContained(root: string, candidate: string, content: string, boundaryLabel: string): Promise<void> {
  const target = resolveContainedPath(root, candidate, boundaryLabel);
  await ensureSafeParents(root, path.dirname(target), boundaryLabel);
  await assertSafeTarget(target, boundaryLabel);
  const temporary = path.join(path.dirname(target), `.${path.basename(target)}.${randomUUID()}.tmp`);
  const handle = await open(temporary, "wx");
  try {
    await handle.writeFile(content, "utf8");
    await handle.sync();
  } finally {
    await handle.close();
  }
  try {
    await operationHook?.("before-final-write-check", target);
    await assertSafeAncestry(root, path.dirname(target), boundaryLabel, true);
    await assertSafeTarget(target, boundaryLabel);
    await rename(temporary, target);
  } catch (error) {
    await unlink(temporary).catch(() => undefined);
    throw error;
  }
}

export async function unlinkContained(root: string, candidate: string, boundaryLabel: string): Promise<void> {
  const target = resolveContainedPath(root, candidate, boundaryLabel);
  await operationHook?.("before-final-delete-check", target);
  await assertSafeAncestry(root, target, boundaryLabel, true);
  const stat = await lstat(target);
  if (stat.isSymbolicLink()) throw new Error(`Refusing symlink or junction deletion outside safe ${boundaryLabel}: ${candidate}`);
  await unlink(target);
}

async function ensureSafeParents(root: string, targetParent: string, boundaryLabel: string): Promise<void> {
  const resolvedRoot = path.resolve(root);
  await mkdir(resolvedRoot, { recursive: true });
  const rootStat = await lstat(resolvedRoot);
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) throw new Error(`Unsafe ${boundaryLabel} root`);
  const relative = path.relative(resolvedRoot, targetParent);
  assertAbsoluteContained(resolvedRoot, targetParent, boundaryLabel);
  let current = resolvedRoot;
  for (const segment of relative.split(path.sep).filter(Boolean)) {
    const next = path.join(current, segment);
    try {
      const stat = await lstat(next);
      if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error(`Symlink, junction, or non-directory escapes ${boundaryLabel}: ${next}`);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      try {
        await mkdir(next);
      } catch (mkdirError) {
        if ((mkdirError as NodeJS.ErrnoException).code !== "EEXIST") throw mkdirError;
      }
      const created = await lstat(next);
      if (created.isSymbolicLink() || !created.isDirectory()) throw new Error(`Unsafe parent created in ${boundaryLabel}: ${next}`);
    }
    current = next;
  }
}

async function assertSafeAncestry(root: string, target: string, boundaryLabel: string, includeTarget: boolean): Promise<void> {
  const resolvedRoot = path.resolve(root);
  assertAbsoluteContained(resolvedRoot, target, boundaryLabel);
  const rootStat = await lstat(resolvedRoot);
  if (rootStat.isSymbolicLink() || !rootStat.isDirectory()) throw new Error(`Unsafe ${boundaryLabel} root`);
  const relative = path.relative(resolvedRoot, includeTarget ? target : path.dirname(target));
  let current = resolvedRoot;
  for (const segment of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);
    const stat = await lstat(current);
    if (stat.isSymbolicLink()) throw new Error(`Symlink or junction escapes ${boundaryLabel}: ${current}`);
  }
}

async function assertSafeTarget(target: string, boundaryLabel: string): Promise<void> {
  try {
    const stat = await lstat(target);
    if (stat.isSymbolicLink() || stat.isDirectory()) throw new Error(`Unsafe destination in ${boundaryLabel}: ${target}`);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
}

function assertAbsoluteContained(root: string, target: string, boundaryLabel: string): void {
  const relative = path.relative(path.resolve(root), path.resolve(target));
  if (relative === "") return;
  if (relative === ".." || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative) || path.win32.isAbsolute(relative)) {
    throw new Error(`Resolved path is outside ${boundaryLabel}: ${target}`);
  }
}

// Node exposes no portable directory-handle-relative rename/unlink API. Final
// ancestry checks narrow the race window and fail closed for detectable swaps,
// but cannot guarantee safety against a privileged process racing after them.
