import * as TOML from "@iarna/toml";
import * as jsoncParser from "jsonc-parser";
import type { ParseError } from "jsonc-parser";

const { applyEdits, modify, parse } = jsoncParser;

export function setJsoncValue(source: string, keyPath: (string | number)[], value: unknown): string {
  const hasBom = source.startsWith("\uFEFF");
  const normalized = hasBom ? source.slice(1) : source;
  const base = normalized.trim() ? normalized : "{}\n";
  const errors: ParseError[] = [];
  parse(base, errors, { allowTrailingComma: true, disallowComments: false });
  if (errors.length) throw new Error("Cannot safely merge malformed JSONC configuration");
  const updated = applyEdits(base, modify(base, keyPath, value, { formattingOptions: { insertSpaces: true, tabSize: 2, eol: "\n" } }));
  return hasBom ? `\uFEFF${updated}` : updated;
}

export function getJsoncValue(source: string, keyPath: (string | number)[]): { exists: boolean; value: unknown } {
  const errors: ParseError[] = [];
  const normalized = source.startsWith("\uFEFF") ? source.slice(1) : source;
  let current = parse(normalized.trim() ? normalized : "{}", errors, { allowTrailingComma: true, disallowComments: false }) as unknown;
  if (errors.length) throw new Error("Cannot safely parse malformed JSONC configuration");
  for (const key of keyPath) {
    if (!current || typeof current !== "object" || !(key in current)) return { exists: false, value: undefined };
    current = (current as Record<string | number, unknown>)[key];
  }
  return { exists: true, value: current };
}

export function getTomlRootString(source: string, key: string): { exists: boolean; value: string | undefined } {
  const parsed = TOML.parse(source.trim() ? source : "") as Record<string, unknown>;
  if (!(key in parsed)) return { exists: false, value: undefined };
  if (typeof parsed[key] !== "string") throw new Error(`TOML root key ${key} must be a string`);
  return { exists: true, value: parsed[key] };
}

export function setTomlRootString(source: string, key: string, value: string | undefined): string {
  if (source.trim()) TOML.parse(source);
  const span = findTomlRootStringSpan(source, key);
  const replacement = value === undefined ? "" : `${key} = ${JSON.stringify(value)}\n`;
  let result: string;
  if (span) {
    result = `${source.slice(0, span.start)}${replacement}${source.slice(span.end)}`;
  } else if (value === undefined) {
    return source;
  } else {
    const table = source.search(/^\s*\[/m);
    const insertAt = table < 0 ? source.length : table;
    const before = source.slice(0, insertAt);
    const after = source.slice(insertAt);
    result = `${before}${before && !before.endsWith("\n") ? "\n" : ""}${replacement}${after && !after.startsWith("\n") ? "\n" : ""}${after}`;
  }
  result = result.replace(/\n{3,}/g, "\n\n");
  if (result.trim()) TOML.parse(result);
  return result.trimEnd() ? `${result.trimEnd()}\n` : "";
}

function findTomlRootStringSpan(source: string, key: string): { start: number; end: number } | undefined {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const matcher = new RegExp(`^[ \\t]*${escaped}[ \\t]*=[ \\t]*(.*)$`);
  let offset = 0;
  let line: RegExpExecArray | undefined;
  let lineStart = 0;
  for (const raw of source.split(/(?<=\n)/)) {
    const text = raw.replace(/\r?\n$/, "");
    if (/^[ \\t]*\[/.test(text)) break;
    const match = matcher.exec(text);
    if (match) {
      line = match;
      lineStart = offset;
      break;
    }
    offset += raw.length;
  }
  if (!line) return undefined;
  const valueStart = lineStart + line[0].indexOf(line[1]);
  const triple = line[1].match(/^("""|''')/u)?.[1];
  if (!triple) {
    const newline = source.indexOf("\n", lineStart);
    return { start: lineStart, end: newline < 0 ? source.length : newline + 1 };
  }
  const sameLineClose = line[1].indexOf(triple, triple.length);
  if (sameLineClose >= 0) {
    const newline = source.indexOf("\n", lineStart);
    return { start: lineStart, end: newline < 0 ? source.length : newline + 1 };
  }
  const close = source.indexOf(triple, valueStart + triple.length);
  if (close < 0) throw new Error(`Unterminated TOML multiline string for ${key}`);
  const newline = source.indexOf("\n", close + triple.length);
  return { start: lineStart, end: newline < 0 ? source.length : newline + 1 };
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
