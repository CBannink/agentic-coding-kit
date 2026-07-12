#!/usr/bin/env bash
set -euo pipefail

target="${1:-${TMPDIR:-/tmp}/agentic-kit-smoke-$(date +%Y%m%d-%H%M%S)}"
if [[ -e "$target" ]]; then
  echo "Target already exists: $target" >&2
  exit 1
fi

mkdir -p "$target/src" "$target/test"
cat >"$target/package.json" <<'EOF'
{
  "name": "agentic-kit-smoke",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
EOF
cat >"$target/src/normalize-tags.js" <<'EOF'
export function normalizeTags(tags) {
  return tags.map((tag) => tag.trim());
}
EOF
cat >"$target/test/normalize-tags.test.js" <<'EOF'
import assert from "node:assert/strict";
import test from "node:test";
import { normalizeTags } from "../src/normalize-tags.js";

test("trims tags", () => {
  assert.deepEqual(normalizeTags([" News ", "Tech"]), ["News", "Tech"]);
});
EOF
cat >"$target/SMOKE-TEST.md" <<'EOF'
# Agentic Coding Kit fresh-instance smoke test

The repository contains a deliberately incomplete `normalizeTags` function.
Do not solve it manually before testing a harness.

Expected workflow behavior:

1. The main session owns orchestration; it does not spawn an orchestrator child.
2. It selects the `build` skill.
3. A coder owns the production change and minimum acceptance tests.
4. Cheap executable checks run before independent review.
5. An independent reviewer evaluates the change.
6. An independent Test Engineer derives boundary cases and may edit tests only.
7. Final evidence is fresh after the last edit.
8. No `.kit`, memory, reflection, task-history, or automatic `.wiki` artifact is created.

Acceptance behavior:

- trim surrounding whitespace;
- lowercase tags;
- discard blank tags;
- remove duplicates after normalization while preserving first-seen order;
- reject non-array input with a `TypeError`.

Required proof: `npm test` passes after the final edit.
EOF
cat >"$target/PROMPTS.md" <<'EOF'
# Prompts

## Interrogate before editing

Do not edit files yet. Inspect the installed Agentic Coding Kit and answer:
1. What are its seven portable skills?
2. Which role owns production changes?
3. In what order do fast checks, independent review, independent test hardening,
   and final verification occur?
4. Can the Test Engineer edit production code?
5. Does the kit use a goal-orchestrator or write automatic memory?

## Build task

Read SMOKE-TEST.md and use the build skill to implement the requested behavior.
Exercise the installed native agents and follow the kit's independent review and
test-hardening policy. Do not create .kit, session memory, reflection files, or
wiki task history. Finish by reporting the agents used and fresh command evidence.

Host invocation:
- Codex: `$build Read SMOKE-TEST.md and complete the smoke task.`
- Claude Code: `/build Read SMOKE-TEST.md and complete the smoke task.`
- OpenCode: `/build Read SMOKE-TEST.md and complete the smoke task.`
- Copilot CLI: `Use the build skill to read SMOKE-TEST.md and complete the smoke task.`
EOF

git -C "$target" init --quiet
git -C "$target" add .
git -C "$target" -c user.name='Agentic Kit Smoke' -c user.email='smoke@example.invalid' commit --quiet -m 'Create harness smoke fixture'

echo "Created smoke repository: $target"
echo "First paste the interrogation prompt from PROMPTS.md into a fresh harness instance."
echo "Then run that host's build invocation from PROMPTS.md."
