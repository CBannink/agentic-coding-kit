# Wiki Index

Canonical entry point for repo-local user-facing docs.

## Sections

| File | Purpose | Key files |
|---|---|---|
| `architecture.md` | Cross-cutting architecture overview, boundaries, and dependency rules | `.wiki/architecture.md` |
| `codebase.md` | Where major code lives and the repo's preferred coding conventions | `.wiki/codebase.md` |
| `features.md` | Human-readable catalog of user-visible capabilities | `.wiki/features.md`, `.wiki/.features` |

## Notes

- Keep `features.md` and `.features` in sync.
- Keep `architecture.md` and `codebase.md` concise enough to load during coding.
- Add more wiki sections here as the repo grows.
- Agents should read this file first before resolving deeper wiki sections.
