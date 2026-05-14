# Copilot CLI -- Model Routing for the Caspar Bannink Agentic Coding Kit

This file is **specific to GitHub Copilot CLI**. Other harnesses (Claude
Code / OpenCode / Codex / Kilo) use a single provider per session and
ignore the routing below -- the kit's global skills are model-agnostic
by design.

Copilot CLI routes between providers (Anthropic + OpenAI) within one
session. The kit's recommended ensemble pattern uses cross-provider
diversity to catch blind spots a single-provider review would miss.

> **Note**: As of 2026-05, `model-selector.ps1` automates this routing.
> The goal-orchestrator calls it before every subagent spawn. You only need
> this document if you want to understand or override the defaults.
> Override via env vars: `MODEL_FAST`, `MODEL_BALANCED`, `MODEL_PREMIUM`,
> or via `MODEL_MAP_FILE` pointing to a JSON override file.

## Recommended ensemble (Copilot CLI only)

| Role | Model | Rationale |
|---|---|---|
| Orchestrator | `gpt-5.4` | Reasoning + cross-provider lead |
| Implementer | `gpt-5.4` | Same cost as gpt-5.3-codex; outperforms on coding |
| Explorer (codebase / patterns / delta) | `gpt-5.4-mini` | 0.33x cost; GitHub-recommended for agentic exploration |
| Spec reviewer | `claude-sonnet-4.6` | Compliance + plan adherence; balanced |
| Code-quality reviewer | `claude-sonnet-4.6` | Maintainability + test quality |
| Modularity expert | `gpt-5.4` | Architecture pressure; cross-provider check on quality reviewer |
| Security reviewer | `claude-sonnet-4.6` | Trust boundaries + injection |
| Adversarial reviewer | `gpt-5.4` | Cross-provider posture vs Claude reviewers |
| Final verifier | `claude-sonnet-4.6` | Iron Law gate; reads code in context |
| QA reviewer | `claude-sonnet-4.6` | Browser / user-flow QA |
| UX strategist (ui-ux expert) | `gpt-5.4` | UX/design critique (Gemini was the original target; gpt-5.4 is the fallback) |
| UI implementer (ui-ux expert) | `claude-sonnet-4.6` | Component structure + Stitch MCP |

## Why this is Copilot-only

The previous version of the kit baked these model names into the global
skill files (`bundle/global/.agents/skills/**/SKILL.md`) and adapter
configs. That broke cross-harness install:

- **Claude Code**: `model: gpt-5.4` is invalid (Claude can't run GPT).
- **OpenCode**: expects `provider/model` format, not bare names.
- **Codex / Kilo**: ignore the field entirely.

The fix: strip model specs from the global skills. Each harness uses its
default. Copilot users who want the ensemble pattern apply it via this
doc when invoking subagents (e.g., pass `--model gpt-5.4` flags into the
agent dispatch when running through Copilot's multi-provider routing).

## Translating "premium reasoning model" / "balanced model" / "fast model"

The global skills now use neutral capability descriptors. Map them to
your provider when running on Copilot:

| Descriptor | Copilot route |
|---|---|
| premium reasoning model | `gpt-5.4` (or `claude-opus-4.7` for Claude-side reasoning) |
| balanced model | `claude-sonnet-4.6` |
| fast explorer model | `gpt-5.4-mini` |
| fast model | `claude-haiku-4.5` |

For Claude Code / OpenCode users: ignore this file. Your harness's default
model is fine. The ensemble pattern doesn't apply because you only have
one provider.
