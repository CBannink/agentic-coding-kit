# Tier-C TODO — kit hardening backlog

Backlog of issues identified during the multi-agent /review on 2026-05-07
that were intentionally deferred from the Tier-B harness-fix sweep
(branch `feat/tier-b-harness-fixes`, commits 67bb3c0..771fb28). One
section per item with severity, files, summary, and why deferred.

The 7 Tier-B fixes that DID land in that branch are listed at the bottom
for cross-reference.

---

## C1. Schedule periodic `compress-memory.ps1` and rotate `reflections.md`

**Severity**: HIGH (operational)
**Files**:
- `bundle/global/.agents/tools/compress-memory.ps1` (default `SessionStateAgeDays = 60`)
- `bundle/global/.agents/tools/post-session.ps1` (current sole caller)
- `bundle/global/.agents/context/reflections.md` (not in compress-memory's rotation set today)
- `scripts/install.ps1` (would need new Task Scheduler / cron / launchd registration)

**Fix**: register compress-memory.ps1 as a recurring job at install time
(Windows Task Scheduler, macOS launchd, Linux cron). Add reflections.md
to the rotation target list. Surface a warning in `doctor.ps1` when
`~/.agents/session-state` exceeds 100 MB.

**Why deferred from Tier B**: scheduling is host-OS-specific and adds
substantial install-platform code. Tier B's session-state preservation
fix (P3) prevents the OTHER half of the problem (the wipe), so users no
longer LOSE state — they just accumulate it. The accumulation is a
slower-moving issue.

---

## C2. Consolidate specialist agents into `_shared/specialist-agents/`

**Severity**: MEDIUM
**Files**:
- `bundle/adapters/claude-code/.claude/agents/*.md` (10 specialist agents)
- `bundle/adapters/opencode/.opencode/agents/*.md` (10 parallel copies)
- `bundle/adapters/copilot-cli/.github/agents/*.agent.md` (10 generated copies, post-P4)
- `scripts/install.ps1` `Install-DeviceWideAgents` (lines ~600+) and the
  per-host dispatch branches at lines ~900+ and ~1000+

**Fix**: move the canonical agent bodies into `bundle/adapters/_shared/specialist-agents/`
with `__HOST_NAME__` placeholder. Have install.ps1 render per-host with the
right frontmatter:
- Claude: name + description + model + tools + permissionMode + maxTurns
- OpenCode: name + description + mode: subagent
- Copilot: name + description (`.agent.md` extension)

Delete the per-host copies after migration.

**Why deferred from Tier B**: the f714a3b refactor closed the workflow-commands
drift class but stopped short of specialist-agents. Tier B was scoped to harness
fixes (install plumbing, hooks, gate proofs); this is architectural reuse work
that's better as its own focused commit. Without it, a description tweak to
`code-quality-reviewer` requires editing 3 files.

Related: workflow-agents dir pruning (Tier B P7) is currently disabled because
the dir has TWO contributors (workflow-agents + specialist-agents). Once C2
lands, the pruning logic can be union-aware and turned on for that dir too.

---

## C3. Fix dangling `~/.agents/workflows/plugins/...` references in skills

**Severity**: MEDIUM
**Files**:
- `bundle/global/.agents/skills/build/SKILL.md` (Plugin Registry table)
- `bundle/global/.agents/skills/review/SKILL.md` (similar)
- Possibly `~/.agents/workflows/plugins/` — does NOT exist in the bundle

**Fix**: rewrite the Plugin Registry tables to point at the real paths under
`bundle/global/.agents/skills/gstack-*` and `bundle/global/.agents/skills/experts/`.
Sub-agents currently get instructed to "Read [plugin path]" and hit ENOENT;
they fall back to baked-in skill content (so degraded, not broken).

**Why deferred**: cosmetic correctness. Functionality holds via fallback.

---

## C4. `pretool-bash-dispatcher.ps1` false-positive on `2>/dev/null`

**Severity**: MEDIUM (operational annoyance — hit during this very review)
**Files**: `bundle/global/.agents/tools/hooks/pretool-bash-dispatcher.ps1`

**Symptom**: regex matches `/dev/` as "destructive at system level" and blocks
any command containing `2>/dev/null` or `>/dev/null`. `/dev/null` is the
universal bit-bucket and not a destructive write target.

**Fix**: in the dangerous-fs check, exempt the literal `/dev/null` (and
`>/dev/null`, `2>/dev/null`, `&>/dev/null`) before the broader `/dev/`
regex fires.

**Why deferred**: workaround exists (avoid the redirect). Doesn't block real
user work, only operator convenience.

---

## C5. Rename Claude-specific hook env-vars to `KIT_*`

**Severity**: MEDIUM
**Files**:
- `bundle/adapters/claude-code/.claude/settings.snippet.json` (line 10:
  `${CLAUDE_SESSION_ID}`, `${CLAUDE_MODE:-build}`, `${CLAUDE_PROJECT_DIR}`)
- `bundle/global/.agents/tools/sync-all-hosts.ps1` env-var translation maps
  (`ClaudeMap`, `GeminiMap`, `CodexMap`, `OpenCodeMap`)
- The kit's hook scripts that read those env-vars

**Fix**: rename `CLAUDE_SESSION_ID` → `KIT_SESSION_ID`, etc. Each adapter's
install branch exports the right value before invoking `_run-ps.sh`. Eliminates
the Claude-isms-everywhere drift documented in the global instructions.

**Why deferred**: high blast-radius rename. Each touched script needs a
back-compat alias period (read both old and new names). Better as its own
commit with explicit before/after diff.

---

## C6. Compress per-adapter initial-load files

**Severity**: LOW–MEDIUM (cost reduction)
**Files**:
- `bundle/adapters/claude-code/CLAUDE.md` (102 lines)
- `bundle/adapters/copilot-cli/.github/copilot-instructions.md` (~145 lines, less
  after Tier-B P4 corrections)
- `bundle/adapters/opencode/AGENTS.md` (72 lines)
- `bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` (181 lines)
- `bundle/adapters/codex-cli/AGENTS.md` (65 lines)
- `bundle/adapters/gemini-cli/GEMINI.md` (96 lines)

**Symptom**: per-host adapter files duplicate content from
`_shared/AGENT-INSTRUCTIONS.md` rather than referencing it. Per-session token
cost is higher than necessary; estimated savings ~6,600 tokens per Claude
session after Tier-B P1 deduped the canonical block (which was the bigger
win).

**Fix**: compress each per-host file to ~30–50 lines of host-specific notes
plus a one-line pointer to `_shared/AGENT-INSTRUCTIONS.md`. Strip duplicated
sections (core operating rules, startup preflight, verification freshness,
memory routing tables) that already live in the shared body.

**Why deferred**: pure optimization. After P1's marker dedupe, the cost
problem is much smaller. Pick this up when the instruction file editing
patterns settle.

---

## C7. Add `playwright-navigator.md` for Claude; tighten ux/ui-driver descriptions

**Severity**: LOW
**Files**:
- `bundle/adapters/claude-code/.claude/agents/playwright-navigator.md` (missing)
- `bundle/adapters/claude-code/.claude/agents/ux-driver.md`
- `bundle/adapters/claude-code/.claude/agents/ui-driver.md`

**Fix**: add the missing agent. Rewrite the ux-driver/ui-driver `description:`
fields so auto-routing fires on natural-language triggers ("does the layout
work", "looks ugly") instead of unusual phrases ("structurally right").

**Why deferred**: trivial polish. Auto-routing still works; the agents are
loaded, just need higher-quality trigger phrases.

---

## C8. Single canonical-source for the kit-block content

**Severity**: MEDIUM (architectural debt surfaced during P1)
**Files**:
- `bundle/global/.agents/global-instructions.md` (305 lines, used by
  `sync-all-hosts.ps1` + `install-{copilot,codex,gemini,opencode}-kit.ps1`)
- `bundle/adapters/_shared/AGENT-INSTRUCTIONS.md` (181 lines, used by
  `scripts/install.ps1` `Install-DeviceWideAlwaysOnRules`)

**Symptom**: TWO different "canonical" kit instructions live in the bundle.
`install.ps1` (the user-facing entry point) writes one body; `sync-all-hosts.ps1`
(the standalone refresh utility) writes a different body. Even with Tier-B P1's
unified markers, the CONTENT inside the markers can diverge depending on
which writer last touched the file.

**Fix**: pick one canonical source and have both writers read from it. Likely
target: `bundle/global/.agents/global-instructions.md` since most installers
already reference it. Update `install.ps1`'s `Install-DeviceWideAlwaysOnRules`
to read that file instead of `_shared/AGENT-INSTRUCTIONS.md`.

**Why deferred from Tier B**: P1 was scoped to marker unification; canonical-
source unification is a content decision (which body is "right"?). Worth
doing carefully.

---

## C9. Delete dead `Install-DeviceWideCompanion` function

**Severity**: LOW (code hygiene)
**Files**: `scripts/install.ps1` lines 561–698

**Symptom**: function defined but never called (dispatch switch at line ~720
goes through `Install-DeviceWideRulesDoc`, `Install-DeviceWideAlwaysOnRules`,
or `Install-DeviceWideInlineInstructions` instead). Tier-B P1 updated its
markers for consistency rather than deleting it.

**Fix**: delete the function and its inline rules block. `git blame` will
preserve history if anyone needs to recover.

---

## C10. Skill `memory.md` merge strategy on re-install

**Severity**: MEDIUM
**Files**:
- `bundle/global/.agents/skills/<name>/memory.md` (6 files in bundle today,
  shipped as starter content)
- `scripts/install.ps1` (`-InstallGlobal` Copy-Tree wipes and replaces)

**Symptom**: Tier-B P3 preserves `session-state/`, `context/handoffs.md`,
`context/reflections.md`, and `inspiration/` across re-installs. Skill
`memory.md` files were NOT preserved because they ship as bundle content
that does get appended-to by users — a real merge problem.

**Fix**: detect divergence between bundle-shipped baseline and on-disk file
(hash baseline at first-install time, compare on re-install). If user has
appended entries, preserve user content and append any new bundle entries
inline. Alternatively, separate user-appended entries into a sibling
`memory.user.md` per skill and only manage `memory.md` from the bundle.

**Why deferred from Tier B**: real merge logic; deferred from P3 with explicit
note in the commit message.

---

## C11. Kilocode parallel command set still drifts

**Severity**: MEDIUM
**Files**:
- `bundle/adapters/kilocode/.kilocode/rules/{build,plan,redesign,review,security-review}.md` (5 hand-curated commands)
- `bundle/adapters/_shared/workflow-commands/*.md` (12 shared commands)
- `scripts/install.ps1` `Get-WorkflowAdapterDestinations` (no `kilocode` case)

**Symptom**: f714a3b consolidated commands for Claude/OpenCode but kilocode
kept its hand-curated subset. The drift class the refactor was supposed to
kill is still alive there. Tier-B P4 addressed Copilot but not kilocode.

**Fix**: add `kilocode` case to `Get-WorkflowAdapterDestinations` (target
`<repo>/.kilocode/rules/`) and route kilocode through `Install-WorkflowAdapterAssets`.
Delete the hand-curated `bundle/adapters/kilocode/.kilocode/rules/*.md` after
migration. OR document the exclusion explicitly with rationale.

---

## C12. Copilot CLI: hook-blocking limitation

**Severity**: LOW (documented limitation)
**Files**: `bundle/adapters/copilot-cli/.github/copilot-instructions.md`
(Tier-B P4 documented this)

**Symptom**: per the docs, Copilot CLI hooks log-and-skip on non-zero exit
instead of exit-2-aborting like Claude Code. The Iron Law gate (P5) is
best-effort on Copilot — the hook fires and records, but cannot abort the
tool call that triggered it.

**Fix**: track GitHub's Copilot CLI hook semantics for changes (issue tracker
or changelog watch). If GitHub adds an exit-2-blocking mode, wire it up. Until
then, accept the best-effort behavior and document it (already done in P4).

---

## C13. Copilot CLI: agent frontmatter schema partial

**Severity**: LOW
**Files**: `bundle/adapters/copilot-cli/.github/agents/*.agent.md`

**Symptom**: Copilot's how-to page documents only `name` and `tools` keys
explicitly; the full schema is not published. Kit ships minimal frontmatter
(name + description) which works but may underutilize the surface.

**Fix**: when GitHub publishes the schema, extend
`Install-CopilotAgentsFromClaudeSource` to emit the additional documented
keys (model selection, tool restrictions, etc.).

---

## C14. Copilot CLI: no `/skills` auto-discovery

**Severity**: LOW
**Files**: `bundle/adapters/copilot-cli/.github/copilot-instructions.md`

**Symptom**: research found no documented `~/.copilot/skills/<name>/SKILL.md`
auto-discovery surface on Copilot CLI as of May 2026, despite earlier kit
documentation claiming it. The kit's procedural workflow content lives
inline in `copilot-instructions.md` instead.

**Fix**: monitor for a published Copilot skills surface. If/when GitHub
ships it, wire skills install into the Copilot device-wide branch.

---

## Tier-B fixes already shipped in this branch

For cross-reference, here is what `feat/tier-b-harness-fixes` did land:

| Commit | Item | Summary |
|---|---|---|
| 67bb3c0 | P1 (CRITICAL) | Unify kit-block markers across all writers; canonical source no longer embeds markers; `-RepairKitBlock` cleanup mode |
| 1c4e359 | P2 (CRITICAL) | De-hardcode `caspar_bannink/Downloads/...` path; install-copilot-kit.ps1 now machine-independent; validate-bundle.ps1 detector extended |
| 74dfdce | P3 (CRITICAL) | Preserve `session-state/`, `context/handoffs.md`, `context/reflections.md`, `inspiration/` across global re-install |
| 1ea3e31 | P6 (HIGH)    | OpenCode: per-repo path corrected to `.opencode/`; agents source moved; `mode: subagent` added; AGENTS.md target replaces prompt.md |
| f3c5e1a | P7 (HIGH)    | Prune stale per-host command files via `-PruneStaleAssets`; backups not hard deletes |
| c0bcc65 | P4 (HIGH)    | Copilot CLI: 15 `.agent.md` files + 4 hook configs; install.ps1 wired (user-scope agents, repo-scope hooks); copilot-instructions.md de-lied; README updated |
| 771fb28 | P5 (HIGH)    | Iron Law: structured `verification_proofs` tuple (cmd + exit_code + output_hash) required when `-WithExitCode` is set; OpenCode plugin no longer manufactures exit_code=0 |
