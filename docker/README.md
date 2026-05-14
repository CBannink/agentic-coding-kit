# Docker — single-image runtime

Pre-baked image: pwsh 7, Python+playwright, Node+OpenCode CLI, kit installed device-wide.

## Build

```bash
docker build -t agentic-kit:latest .
# or via compose
docker compose build
```

First build downloads the Microsoft pwsh image, installs apt packages, pulls Chromium for Playwright, and runs `install.ps1 -DeviceWide all` inside the image. Roughly 2–5 minutes depending on your network. Final image is ~1.5 GB (pwsh + Chromium + Node ecosystem are the bulk).

## Run

### Interactive (default)

```bash
docker run -it --rm \
  -v "$PWD:/workspace" \
  -e KIMI_API_KEY=... \
  agentic-kit:latest
```

You land in `/workspace` (your project) with the kit installed at `~/.agents`. The banner reminds you of the basics.

### Compose (recommended for repeated use)

Create a `.env` next to `docker-compose.yml`:

```bash
KIMI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
OPENROUTER_API_KEY=...
```

Then:

```bash
docker compose run --rm kit                  # interactive shell
docker compose run --rm kit opencode         # straight into OpenCode REPL
docker compose run --rm kit pwsh ~/.agents/tools/doctor.ps1
```

Compose persists three volumes across runs so you don't re-auth every time:

- `kit-opencode` → `/root/.config/opencode/` (auth, settings)
- `kit-session` → `/root/.agents/session-state/` (handoffs, INDEX.md, evidence)
- `kit-proposals` → `/root/.agents/proposals/` (harness proposals, decisions)

## Free-tier path (no API key)

OpenCode supports OpenRouter's free distilled models for prototyping. Set up:

```bash
docker compose run --rm kit
# inside the container:
opencode auth
# pick OpenRouter, paste a free OpenRouter key
# free models include: deepseek-r1-distill, llama-3-3-70b, etc.
```

You'll get rate-limited but functional access at zero cost while you decide whether to pay for Kimi K2.6 or DeepSeek V4 Pro.

## What's inside

```
/opt/agentic-kit/        # the kit source (read-only)
/root/.agents/           # tools, skills, context (writable; persistent if you mount)
/root/.codex/            # global workflow plugins
/root/.claude/           # CLAUDE.md + agentic-kit.md companion
/root/.config/opencode/  # OpenCode config + agentic-kit.ts plugin
/workspace/              # your project (mount-point)
```

## Verifying the install

```bash
docker compose run --rm kit pwsh ~/.agents/tools/doctor.ps1
# expects: PASS on PS version (pwsh 7+ inside container), structure, hooks, plugin
# WARN possible on companion files if you've stripped them post-install
```

## Updating

```bash
git pull           # update the kit source
docker compose build --no-cache kit
```

The persisted volumes (auth, session-state, proposals) survive the rebuild. If you want a fully clean slate:

```bash
docker compose down -v
docker compose build
```

## Why bother with Docker

- **Reproducibility**: anyone can pull the image and run, no local pwsh / Python / Node install required.
- **Isolation**: kit edits stay inside the container; your host `~/.agents` isn't touched.
- **CI/CD**: same image in dev and CI means your harness behaves the same in both.
- **Try-before-you-install**: spin up, evaluate, throw away. No commitment.

## Why NOT use Docker

- The kit is designed to integrate with your host CLIs (Claude Code, Codex CLI, OpenCode). Inside Docker you only get OpenCode (no Claude Code or Codex CLI binaries).
- Slight friction: `docker compose run` vs just `opencode` on host.
- File-watching across the bind mount can be slower on macOS / Windows hosts.

For solo dev usage with a stable setup, the direct host install (`scripts/install.ps1 -DeviceWide all`) is usually nicer. Docker shines for: reproducibility, sharing with collaborators, CI runs, and trying the kit without committing to a host install.
