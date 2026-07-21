import * as TOML from "@iarna/toml";
import matter from "gray-matter";
import * as jsoncParser from "jsonc-parser";
import type { ParseError } from "jsonc-parser";
import YAML from "yaml";

const { parse: parseJsoncText, parseTree, printParseErrorCode } = jsoncParser;

export interface FrontmatterDocument<T extends Record<string, unknown> = Record<string, unknown>> {
  data: T;
  content: string;
}

export function parseYaml<T = unknown>(source: string): T {
  return YAML.parse(source) as T;
}

export function serializeYaml(value: unknown): string {
  return YAML.stringify(value, { lineWidth: 0 });
}

export function parseToml<T = unknown>(source: string): T {
  return TOML.parse(source) as T;
}

export function serializeToml(value: TOML.JsonMap): string {
  return TOML.stringify(value);
}

export function parseJsonc<T = unknown>(source: string): T {
  const input = source.charCodeAt(0) === 0xfeff ? source.slice(1) : source;
  const errors: ParseError[] = [];
  const value = parseJsoncText(input, errors, { allowTrailingComma: true, disallowComments: false });
  if (errors.length > 0 || !parseTree(input, [], { allowTrailingComma: true, disallowComments: false })) {
    const detail = errors.map((error) => `${printParseErrorCode(error.error)}@${error.offset}`).join(", ");
    throw new Error(`Invalid JSONC: ${detail || "no parse tree"}`);
  }
  return value as T;
}

export function parseFrontmatter<T extends Record<string, unknown> = Record<string, unknown>>(source: string): FrontmatterDocument<T> {
  const parsed = matter(source, {
    engines: { yaml: (input: string) => parseYaml(input) as object },
    language: "yaml",
  });
  return { data: parsed.data as T, content: parsed.content };
}

export function serializeFrontmatter(data: Record<string, unknown>, content: string): string {
  const frontmatter = serializeYaml(data).trimEnd();
  return `---\n${frontmatter}\n---\n\n${content.trimStart().trimEnd()}\n`;
}
