import { readFile } from "node:fs/promises";
import path from "node:path";
import { Ajv2020, type ErrorObject } from "ajv/dist/2020.js";
import { parseYaml } from "./parsers.js";
import { resolveExistingContainedPath } from "./paths.js";
import type { AgentDefinition, Manifest } from "./types.js";

const CORE_SKILLS = ["analyze", "architecture", "build", "design", "experiment", "grill", "pr-ready", "review", "threat-model", "wiki"];
const CORE_AGENTS = ["architect", "coder", "diagnostician", "repo-scout", "reviewer", "sage", "security-reviewer", "test-engineer"];
const UI_AGENTS = ["browser-qa", "ui-critic"];

export async function loadManifest(repoRoot: string): Promise<Manifest> {
  const manifestPath = path.join(repoRoot, "core", "manifest.yaml");
  const schemaPath = path.join(repoRoot, "core", "schemas", "manifest.schema.json");
  const [source, schemaSource] = await Promise.all([
    readFile(manifestPath, "utf8"),
    readFile(schemaPath, "utf8"),
  ]);
  const manifest = parseYaml<Manifest>(source);
  const schema = JSON.parse(schemaSource) as object;
  validateManifestSchema(manifest, schema);
  await validateManifestSemantics(repoRoot, manifest);
  return manifest;
}

export function validateManifestSchema(manifest: unknown, schema: object): void {
  const ajv = new Ajv2020({ allErrors: true, strict: true });
  const validate = ajv.compile(schema);
  if (!validate(manifest)) {
    throw new Error(`Manifest schema validation failed:\n${formatAjvErrors(validate.errors)}`);
  }
}

export async function validateManifestSemantics(repoRoot: string, manifest: Manifest): Promise<void> {
  assertExact("core skills", manifest.skills.map((skill) => skill.id), CORE_SKILLS);
  assertExact("core agents", manifest.agents.map((agent) => agent.id), CORE_AGENTS);
  assertExact("UI pack agents", manifest.packs.ui?.agents.map((agent) => agent.id) ?? [], UI_AGENTS);
  assertUnique("skill IDs", manifest.skills.map((skill) => skill.id));
  assertUnique("agent IDs", allAgents(manifest).map((agent) => agent.id));
  for (const skill of manifest.skills) assertCanonicalSource(skill.source, `core/skills/${skill.id}/SKILL.md`, `skill:${skill.id}`);
  for (const agent of manifest.agents) assertCanonicalSource(agent.source, `core/agents/${agent.id}.md`, `agent:${agent.id}`);
  for (const agent of manifest.packs.ui.agents) assertCanonicalSource(agent.source, `packs/ui/agents/${agent.id}.md`, `agent:${agent.id}`);
  assertCanonicalSource(manifest.instruction_fragments.orchestrator, "core/orchestrator.md", "orchestrator");
  assertCanonicalSource(manifest.instruction_fragments.opencode_primary, "core/opencode-primary.md", "OpenCode primary");

  const testEngineer = manifest.agents.find((agent) => agent.id === "test-engineer");
  if (!testEngineer || testEngineer.permission_class !== "test-write") {
    throw new Error("test-engineer must use test-write permissions");
  }
  const allowedTestScopes = ["fixtures", "test-utilities", "tests"];
  assertExact("test-engineer write scope", testEngineer.write_scope ?? [], allowedTestScopes);
  for (const agent of allAgents(manifest)) {
    if (agent.permission_class === "read-only" && (agent.write_scope?.length ?? 0) > 0) {
      throw new Error(`${agent.id} is read-only but declares write_scope`);
    }
    if (!agent.hosts.length) throw new Error(`${agent.id} has no host support`);
  }

  const sourcePaths = [
    manifest.instruction_fragments.orchestrator,
    manifest.instruction_fragments.opencode_primary,
    ...manifest.skills.map((skill) => skill.source),
    ...allAgents(manifest).map((agent) => agent.source),
  ];
  await Promise.all(sourcePaths.map(async (source) => {
    try {
      const safeSource = await resolveExistingContainedPath(repoRoot, source, "repository root");
      await readFile(safeSource, "utf8");
    } catch (error) {
      if (error instanceof Error && /outside|escape|traversal|absolute/i.test(error.message)) throw error;
      throw new Error(`Missing canonical source: ${source}`);
    }
  }));
}

export function allAgents(manifest: Manifest): AgentDefinition[] {
  return [...manifest.agents, ...Object.values(manifest.packs).flatMap((pack) => pack.agents)];
}

function assertUnique(label: string, values: string[]): void {
  if (new Set(values).size !== values.length) throw new Error(`Duplicate ${label}`);
}

function assertExact(label: string, actual: string[], expected: string[]): void {
  const normalized = [...actual].sort();
  if (normalized.join("\n") !== expected.join("\n")) {
    throw new Error(`${label} mismatch: expected ${expected.join(", ")}; got ${normalized.join(", ")}`);
  }
}

function formatAjvErrors(errors: ErrorObject[] | null | undefined): string {
  return (errors ?? []).map((error) => `${error.instancePath || "/"} ${error.message ?? "invalid"}`).join("\n");
}

function assertCanonicalSource(actual: string, expected: string, sourceId: string): void {
  if (actual !== expected) throw new Error(`${sourceId} must use exact canonical source ${expected} to prevent repository root escape; got ${actual}`);
}
