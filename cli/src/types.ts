export type Host = "codex" | "claude" | "opencode" | "copilot";
export type InstallProfile = "core" | "full";
export type PermissionClass = "read-only" | "workspace-write" | "test-write" | "artifact-write";
export type ModelTier = "fast" | "standard" | "deep" | "premium";

export interface SkillDefinition {
  id: string;
  source: string;
  default: boolean;
}

export interface AgentDefinition {
  id: string;
  description: string;
  source: string;
  kind: "subagent" | "primary-profile" | "specialist";
  permission_class: PermissionClass;
  write_scope?: string[];
  model_tier: ModelTier;
  default?: boolean;
  conditional?: boolean;
  hosts: Host[];
  return_packet: string;
}

export interface PackDefinition {
  default: boolean;
  agents: AgentDefinition[];
}

export interface Manifest {
  schema_version: 1;
  kit_version: string;
  model_tiers: Record<ModelTier, { purpose: string }>;
  skills: SkillDefinition[];
  agents: AgentDefinition[];
  packs: Record<string, PackDefinition>;
  instruction_fragments: { orchestrator: string; opencode_primary: string };
}

export interface GeneratedFile {
  path: string;
  content: string;
  sourceId: string;
}

export interface RenderOptions {
  installProfile: InstallProfile;
  commands: boolean;
}
