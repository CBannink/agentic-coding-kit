import * as TOML from "@iarna/toml";
import * as jsoncParser from "jsonc-parser";
import type { ParseError } from "jsonc-parser";

const { applyEdits, modify, parse } = jsoncParser;

export function setJsoncValue(source: string, keyPath: (string | number)[], value: unknown): string {
  const base = source.trim() ? source : "{}\n";
  const errors: ParseError[] = [];
  parse(base, errors, { allowTrailingComma: true, disallowComments: false });
  if (errors.length) throw new Error("Cannot safely merge malformed JSONC configuration");
  return applyEdits(base, modify(base, keyPath, value, { formattingOptions: { insertSpaces: true, tabSize: 2, eol: "\n" } }));
}

export function getJsoncValue(source: string, keyPath: (string | number)[]): { exists: boolean; value: unknown } {
  const errors: ParseError[] = [];
  let current = parse(source.trim() ? source : "{}", errors, { allowTrailingComma: true, disallowComments: false }) as unknown;
  if (errors.length) throw new Error("Cannot safely parse malformed JSONC configuration");
  for (const key of keyPath) {
    if (!current || typeof current !== "object" || !(key in current)) return { exists: false, value: undefined };
    current = (current as Record<string | number, unknown>)[key];
  }
  return { exists: true, value: current };
}

const TOML_START = "# agentic-coding-kit:start";
const TOML_END = "# agentic-coding-kit:end";

export function mergeTomlManagedBlock(source: string, body: string, force = false): string {
  const starts = count(source, TOML_START);
  const ends = count(source, TOML_END);
  if ((starts !== ends || starts > 1) && !force) throw new Error("Malformed or duplicate managed TOML block");
  const cleaned = removeManagedRootKeys(removeTomlManagedBlock(source, force), body);
  const block = `${TOML_START}\n${body.trim()}\n${TOML_END}`;
  const result = `${block}${cleaned.trim() ? `\n\n${cleaned.trimStart()}` : "\n"}`;
  TOML.parse(result);
  return result;
}

export function removeTomlManagedBlock(source: string, force = false): string {
  const starts = count(source, TOML_START);
  const ends = count(source, TOML_END);
  if ((starts !== ends || starts > 1) && !force) throw new Error("Malformed or duplicate managed TOML block");
  if (!starts) return source;
  const start = source.indexOf(TOML_START);
  const end = source.indexOf(TOML_END, start);
  if (end < 0) return force ? source.slice(0, start) : source;
  const managedBody = source.slice(start + TOML_START.length, end);
  const legacyTail = preserveLegacyCodexTables(managedBody);
  const result = `${source.slice(0, start)}${legacyTail}${source.slice(end + TOML_END.length)}`.replace(/\n{3,}/g, "\n\n");
  if (result.trim()) TOML.parse(result);
  return result.trimEnd() ? `${result.trimEnd()}\n` : "";
}

function preserveLegacyCodexTables(body: string): string {
  if (!/^\s*\[profiles\.agentic-kit\]/m.test(body)) return "";
  const headers = [...body.matchAll(/^\s*\[[^\]]+\]\s*$/gm)];
  const next = headers.find((match) => match[0].trim() !== "[profiles.agentic-kit]");
  return next?.index === undefined ? "" : `\n${body.slice(next.index).trim()}\n`;
}

function removeManagedRootKeys(source: string, body: string): string {
  const keys = new Set(
    body.split(/\r?\n/)
      .map((line) => line.match(/^\s*([A-Za-z0-9_.-]+)\s*=/)?.[1])
      .filter((key): key is string => Boolean(key)),
  );
  if (!keys.size) return source;
  let enteredTable = false;
  return source.split(/(?<=\n)/).filter((line) => {
    if (/^\s*\[/.test(line)) enteredTable = true;
    if (enteredTable) return true;
    const key = line.match(/^\s*([A-Za-z0-9_.-]+)\s*=/)?.[1];
    return !key || !keys.has(key);
  }).join("");
}

function count(value: string, needle: string): number { return value.split(needle).length - 1; }
