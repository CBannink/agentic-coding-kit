# Setup and Installation

## Prerequisites

- Windows or macOS.
- Node.js 20 or newer.
- Git for project installs and source inspection.
- At least one separately installed harness: Codex, Claude Code, OpenCode, or
  GitHub Copilot CLI.

Build the management CLI from the repository root:

```text
npm ci --prefix cli
npm run bundle --prefix cli
```

## Install

A user-scope install replaces the selected harness's managed global
instructions, agents, skills, commands, and supported primary configuration.
The installer shows a warning and asks for confirmation; use `--yes` only for a
deliberate non-interactive install.

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-all.ps1 `
  --scope user --profile core --security preserve --memory preserve
```

macOS:

```bash
bash scripts/install-all.sh \
  --scope user --profile core --security preserve --memory preserve
```

Use `install-codex`, `install-claude`, `install-opencode`, or
`install-copilot` for one host. `core` installs the ten skills and eight core
agents; `full` adds Browser QA and UI Critic. Use `--dry-run` to preview.

Project scope writes native repository-local surfaces without clearing
user-global configuration:

```text
node cli/dist/kit.cjs install --host all --scope project --repo <path> --profile core --dry-run
```

## Use

- Codex: `$build`, `$design`, `$architecture`, `$grill`, `$review`,
  `$experiment`.
- Claude Code: `/build`, `/design`, `/architecture`, `/grill`, `/review`,
  `/experiment`.
- OpenCode: `/build` or the native installed skills. ACK installs a managed
  `agentic-kit` primary and preserves an unrelated configured primary unless
  explicit takeover is requested.
- Copilot CLI: ask it to use the installed skill; inspect skills with `/skills`
  and agents with `/agent`.

The primary selects INLINE or LOOP. There is no `/goal` workflow, session-state
bootstrap, lifecycle-hook runtime, or `.kit` memory requirement.

Codex stores the ACK primary in `developer_instructions` while keeping custom
specialists isolated from that policy. OpenCode stores the policy only in the
`agentic-kit` primary; its specialists cannot load workflow skills or dispatch
successors. ACK does not use repository `AGENTS.md` as its global control plane
for either host.

## Repository wiki

`wiki init` and `wiki reinit` are direct skill workflows. After snapshotting
existing human content, the active primary assigns one fresh write-capable Wiki
Page Scout to research and write each repository-local page with normal host
tools: `repository-map.md`, `engineering.md`, `coding.md`, `reviewing.md`,
`testing.md`, and `security.md`, followed by an index Scout that reads those six
pages and writes `index.md`. One optional completeness Reviewer may then check
files/sections, links/anchors, cited paths, and token ceilings without rewriting.
Ceilings are maxima: 500 tokens for the index and 800 tokens for every other
required page. Init creates `.wiki` or fills missing pages; reinit preserves
unrelated or unclear human work unless the user approves a destructive change.

`wiki audit` uses ordinary file and search tools, makes no writes, and reports
missing required files or sections, broken index links, and missing cited paths.
No executable, PATH installation, synthesis artifact, or temporary workflow
state is required. The bundled CLI's wiki commands remain optional tooling for
users who deliberately choose them; inspect their current `--help` before use.

## Verify this repository

```text
npm run typecheck --prefix cli
npm test --prefix cli
npm run validate --prefix cli
npm run check:drift --prefix cli
```

Use `node cli/dist/kit.cjs doctor ...` to inspect a managed host installation.
