import path from "node:path";
import { unified } from "unified";
import remarkParse from "remark-parse";
import { visit } from "unist-util-visit";
import type { GeneratedFile } from "./types.js";

interface LinkNode {
  type: "link";
  url: string;
}

export function findBrokenLocalMarkdownLinks(files: GeneratedFile[]): string[] {
  const available = new Set(files.map((file) => normalize(file.path)));
  const broken: string[] = [];
  for (const file of files.filter((candidate) => candidate.path.endsWith(".md"))) {
    const tree = unified().use(remarkParse).parse(file.content);
    visit(tree, "link", (node: LinkNode) => {
      const url = node.url;
      if (!url || url.startsWith("#") || /^[a-z][a-z0-9+.-]*:/i.test(url)) return;
      let targetPart: string;
      try {
        targetPart = decodeURIComponent(url.split("#", 1)[0]!);
      } catch {
        broken.push(`${normalize(file.path)} -> ${url}`);
        return;
      }
      if (!targetPart) return;
      const target = normalize(path.posix.normalize(path.posix.join(path.posix.dirname(normalize(file.path)), targetPart)));
      if (!available.has(target)) broken.push(`${normalize(file.path)} -> ${url}`);
    });
  }
  return broken.sort();
}

function normalize(value: string): string {
  return value.split(path.sep).join("/");
}
