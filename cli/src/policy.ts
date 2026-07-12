export type BuildPlaybook = "INLINE" | "STANDARD" | "DEEP";
export type DesignPlaybook = "INLINE_DESIGN" | "REVIEWED_DESIGN";

export interface FailureSignatureInput {
  scenario: string;
  failingCase: string;
  primaryError: string;
  changedPaths: string[];
}

export function normalizeFailureSignature(input: FailureSignatureInput): string {
  return [
    input.scenario.trim().replace(/\s+/g, " "),
    input.failingCase.trim().replace(/\s+/g, " "),
    input.primaryError.trim().replace(/\s+/g, " "),
    [...input.changedPaths].sort().join(","),
  ].join("|").toLowerCase();
}

export const DEFAULT_REPAIR_LIMIT = 2;

export interface RepairBudget {
  attempts: number;
  limit: number;
  mayContinue: boolean;
}

/** Records a completed repair attempt whose next applicable gate still failed. */
export function recordUnsuccessfulRepair(
  currentAttempts: number,
  limit = DEFAULT_REPAIR_LIMIT,
): RepairBudget {
  if (!Number.isInteger(currentAttempts) || currentAttempts < 0) {
    throw new Error("Repair attempts must be a non-negative integer");
  }
  if (!Number.isInteger(limit) || limit < 1) {
    throw new Error("Repair limit must be a positive integer");
  }
  const attempts = currentAttempts + 1;
  return { attempts, limit, mayContinue: attempts < limit };
}

export interface RevisionBoundEvidence {
  evidenceRevision: string;
  currentRevision: string;
}

/** Evidence is current only when it applies to the exact current workspace revision. */
export function isEvidenceFresh(evidence: RevisionBoundEvidence): boolean {
  return evidence.evidenceRevision.length > 0
    && evidence.currentRevision.length > 0
    && evidence.evidenceRevision === evidence.currentRevision;
}

export type HandoffKind =
  | "scout"
  | "coder"
  | "review"
  | "test-charter"
  | "test"
  | "failure"
  | "sage";

const requiredHandoffFields: Record<HandoffKind, readonly string[]> = {
  scout: ["status", "missionAnswered", "relevantFlow", "implementationSurface", "verification"],
  coder: ["status", "implemented", "changed", "evidence"],
  review: ["verdict", "contractAssessment", "findings"],
  "test-charter": ["contractBehaviors", "existingEvidence", "highestValueGaps", "chosenTestLevel"],
  test: ["outcome", "evidence"],
  failure: ["failure", "classification", "evidence", "recommendedNextAction"],
  sage: ["question", "recommendation", "confidence"],
};

export interface HandoffValidation {
  valid: boolean;
  missing: string[];
}

/** Structural validation only; the orchestrator must still verify claims in the workspace. */
export function validateHandoff(
  kind: HandoffKind,
  packet: Record<string, unknown>,
): HandoffValidation {
  const missing = requiredHandoffFields[kind].filter((field) => {
    const value = packet[field];
    if (value === undefined || value === null) return true;
    if (typeof value === "string") return value.trim().length === 0;
    // Canonical packets omit empty sections, but an explicitly present empty
    // collection can be meaningful (for example PASS with no findings).
    return false;
  });
  if (kind === "test" && packet.outcome === "CODE_DEFECT") {
    const defectEvidence = packet.defectEvidence;
    if (defectEvidence === undefined || defectEvidence === null
      || (typeof defectEvidence === "string" && defectEvidence.trim().length === 0)) {
      missing.push("defectEvidence");
    }
  }
  if (kind === "coder" && packet.status === "CONTRACT_GAP") {
    const contractGap = packet.contractGap;
    if (contractGap === undefined || contractGap === null
      || (typeof contractGap === "string" && contractGap.trim().length === 0)) {
      missing.push("contractGap");
    }
  }
  return { valid: missing.length === 0, missing };
}

export interface CompletionInput extends RevisionBoundEvidence {
  requestSatisfied: boolean;
  blockingFindings: number;
  materialUnknowns: number;
}

export interface CompletionReadiness {
  ready: boolean;
  reasons: string[];
}

/** Checks deterministic completion invariants without selecting or enforcing a workflow. */
export function evaluateCompletion(input: CompletionInput): CompletionReadiness {
  const reasons: string[] = [];
  if (!input.requestSatisfied) reasons.push("requested outcome is not satisfied");
  if (input.blockingFindings > 0) reasons.push("blocking findings remain");
  if (input.materialUnknowns > 0) reasons.push("material unknowns remain");
  if (!isEvidenceFresh(input)) reasons.push("verification evidence is stale or missing");
  return { ready: reasons.length === 0, reasons };
}
