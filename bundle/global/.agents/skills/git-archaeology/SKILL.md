---
name: git-archaeology
model: gpt-5.4-mini
description: >
  Analyzes the repository's git history (last 100–500 commits) to extract preferred patterns,
  naming conventions, test structure, commit style, directory organization, and technology choices.
  Outputs a compact Project Conventions Profile that implementers use instead of guessing conventions.
  Invoke as Phase 0 in /build, standalone with /git-archaeology, or before /refactor.
---

# Git Archaeology

Analyze this repo's git history to extract how the team **actually** builds things — not how they say they do.

The result is a compact **Conventions Profile** that tells implementers what to copy, not what to invent.

## When to Invoke

- **`/build` Phase 0** (`patterns-explorer` role) when touching existing code — always run first
- **Standalone** when onboarding to an unfamiliar codebase
- **Before `/refactor`** to understand which patterns are intentional vs accidental
- **When conventions are ambiguous** and the codebase itself is the source of truth

---

## Analysis Steps

Run this sequence. Adapt paths if the repo uses a non-standard layout.

**Platform note (Windows)**: commands below use bash/Unix syntax. On Windows PowerShell replace `grep -v "^$"` with `Where-Object { $_ -ne '' }`, `sort | uniq -c | sort -rn | head -40` with `Group-Object | Sort-Object Count -Descending | Select-Object -First 40`, and `grep` with `Select-String`. `git` commands work as-is.

### 1. Commit message style (last 100 commits)
```bash
git log --oneline -100
```
Look for: conventional commits (`feat:`, `fix:`, `chore:`), ticket IDs, past/present tense, scope tags, atomic vs bulk commits.

### 2. New-file patterns (where things land)
```bash
git log --diff-filter=A --name-only --pretty="" -200 | grep -v "^$" | sort | uniq -c | sort -rn | head -40
```
Look for: directory depth, naming style (kebab-case vs PascalCase vs snake_case), co-location of tests.

### 3. Hot files (high churn = fragile or core)
```bash
git log --name-only --pretty="" -200 | grep -v "^$" | sort | uniq -c | sort -rn | head -20
```
High-churn files are either the central modules everyone builds on (watch for regressions) or historically fragile areas (flag to the user before touching).

### 4. Test file patterns
```bash
git log --diff-filter=A --name-only --pretty="" -200 | grep -iE "test|spec" | sort | uniq
```
Look for: `*.test.ts` vs `*.spec.ts`, `__tests__/` folder vs co-location, test naming patterns.

### 5. Change scope per commit (are tests always included?)
```bash
git log --stat -20
```
Look for: ratio of test files to source files per commit. Do features ship without tests? This sets the team's actual standard.

### 6. Technology choices from recent diffs
```bash
git log --oneline -30 --name-only | head -80
```
Then inspect 3-5 recent feature commits:
```bash
git show <sha> -- "*.ts" "*.tsx" "*.py" | grep "^+import\|^+from" | sort | uniq -c | sort -rn | head -20
```
Look for: preferred libraries in new code (state management, HTTP, validation, testing tools).

### 7. Error handling patterns
```bash
git log -p -50 -- "*.ts" "*.tsx" "*.py" | grep "^+" | grep -E "(catch|throw|raise|Error|reject)" | sort | uniq -c | sort -rn | head -20
```
Look for: custom error classes, try/catch depth, `.catch(() => ...)` fallback patterns, error propagation style.

### 8. Any reverts or repeated fixes (antipatterns)
```bash
git log --oneline -100 | grep -iE "revert|fix.*fix|again|oops|undo"
```
These commits reveal patterns the team tried and abandoned. Never repeat them.

---

## Output Format

Produce a **Project Conventions Profile** as a compact block. **Maximum 400 words.** Every item must come from actual git evidence — never assume.

```markdown
## Project Conventions Profile
*Source: last N commits, analyzed by git-archaeology*

**Commit style**: [e.g., conventional commits: `feat(auth): add JWT refresh` — always present-tense imperative]
**Test location**: [e.g., co-located `*.test.ts` files next to source, never in `__tests__/`]
**Test framework**: [e.g., Vitest with `@testing-library/react`, E2E with Playwright]
**Naming**: [e.g., files: kebab-case, components: PascalCase, hooks: camelCase with `use` prefix]
**Error handling**: [e.g., typed error classes extending `AppError`, never empty catch blocks]
**Import style**: [e.g., named imports only, barrel exports via `index.ts`]
**Hot files (fragile — touch carefully)**: [top 3-5 by churn]
**Recent velocity**: [e.g., avg 3 files per commit, tests always included with features]
**Preferred libs in new code**: [e.g., zod for validation, prisma for DB, react-query for async state]
**Antipatterns from reverts**: [patterns that were introduced then undone — never repeat]
**Evidence gaps**: [any area where history is too sparse to draw conclusions]
```

---

## Passing to Implementers

After generating the profile, the orchestrator includes it verbatim in every implementer sub-agent prompt:

```
Here is the Project Conventions Profile extracted from this repo's git history.
Follow these patterns exactly — they reflect how this codebase actually evolves:

[PASTE PROFILE HERE]
```

This replaces the vague instruction "follow existing conventions" with concrete git-backed evidence.

---

## Scope Rules

- Analyze at most **500 commits**. For high-volume repos, cap with `--since "6 months ago"`.
- Only inspect commits on the **default/main branch** unless a feature branch is explicitly specified.
- If the repo has **fewer than 20 commits**: skip analysis and note "insufficient history for pattern extraction."
- **Never write to `memory.md`** from this skill alone — the Conventions Profile is per-session scratch attached to implementer prompts. Promote to `memory.md` only if the orchestrator confirms the patterns are stable and repo-wide.
