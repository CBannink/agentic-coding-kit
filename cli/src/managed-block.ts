export const BLOCK_START = "<!-- agentic-coding-kit:start -->";
export const BLOCK_END = "<!-- agentic-coding-kit:end -->";

export function mergeManagedBlock(existing: string, managedBody: string, force = false): string {
  const starts = count(existing, BLOCK_START);
  const ends = count(existing, BLOCK_END);
  if ((starts !== ends || starts > 1) && !force) throw new Error("Malformed or duplicate Agentic Coding Kit managed block");
  const cleaned = starts ? removeAllBlocks(existing, force) : existing;
  const block = `${BLOCK_START}\n${managedBody.trim()}\n${BLOCK_END}`;
  return `${cleaned.trimEnd()}${cleaned.trim() ? "\n\n" : ""}${block}\n`;
}

export function removeManagedBlock(existing: string, force = false): string {
  const starts = count(existing, BLOCK_START);
  const ends = count(existing, BLOCK_END);
  if ((starts !== ends || starts > 1) && !force) throw new Error("Malformed or duplicate Agentic Coding Kit managed block");
  return `${removeAllBlocks(existing, force).trimEnd()}${existing.trim() ? "\n" : ""}`;
}

export function extractManagedBody(renderedInstruction: string): string {
  const start = renderedInstruction.indexOf(BLOCK_START);
  const end = renderedInstruction.indexOf(BLOCK_END, start + BLOCK_START.length);
  if (start < 0 || end < 0) throw new Error("Rendered instruction lacks managed block");
  return renderedInstruction.slice(start + BLOCK_START.length, end).trim();
}

function removeAllBlocks(value: string, force: boolean): string {
  let output = value;
  while (output.includes(BLOCK_START)) {
    const start = output.indexOf(BLOCK_START);
    const end = output.indexOf(BLOCK_END, start + BLOCK_START.length);
    if (end < 0) {
      if (!force) throw new Error("Malformed managed block");
      output = output.slice(0, start);
      break;
    }
    output = `${output.slice(0, start)}${output.slice(end + BLOCK_END.length)}`;
  }
  return output.replace(/\n{3,}/g, "\n\n");
}

function count(value: string, needle: string): number {
  return value.split(needle).length - 1;
}
