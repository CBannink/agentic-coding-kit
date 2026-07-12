[CmdletBinding()]
param(
    [string]$Target = (Join-Path ([System.IO.Path]::GetTempPath()) ("agentic-kit-smoke-" + (Get-Date -Format "yyyyMMdd-HHmmss")))
)

$ErrorActionPreference = 'Stop'
$Target = [System.IO.Path]::GetFullPath($Target)
if (Test-Path -LiteralPath $Target) {
    throw "Target already exists: $Target"
}

New-Item -ItemType Directory -Path (Join-Path $Target 'src') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Target 'test') -Force | Out-Null

@'
{
  "name": "agentic-kit-smoke",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test"
  }
}
'@ | Set-Content -LiteralPath (Join-Path $Target 'package.json') -Encoding utf8

@'
export function normalizeTags(tags) {
  return tags.map((tag) => tag.trim());
}
'@ | Set-Content -LiteralPath (Join-Path $Target 'src/normalize-tags.js') -Encoding utf8

@'
import assert from "node:assert/strict";
import test from "node:test";
import { normalizeTags } from "../src/normalize-tags.js";

test("trims tags", () => {
  assert.deepEqual(normalizeTags([" News ", "Tech"]), ["News", "Tech"]);
});
'@ | Set-Content -LiteralPath (Join-Path $Target 'test/normalize-tags.test.js') -Encoding utf8

@'
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
'@ | Set-Content -LiteralPath (Join-Path $Target 'SMOKE-TEST.md') -Encoding utf8

@'
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
'@ | Set-Content -LiteralPath (Join-Path $Target 'PROMPTS.md') -Encoding utf8

git -C $Target init --quiet
git -C $Target add .
git -C $Target -c user.name='Agentic Kit Smoke' -c user.email='smoke@example.invalid' commit --quiet -m 'Create harness smoke fixture'

Write-Output "Created smoke repository: $Target"
Write-Output "First paste the interrogation prompt from PROMPTS.md into a fresh harness instance."
Write-Output "Then run that host's build invocation from PROMPTS.md."
