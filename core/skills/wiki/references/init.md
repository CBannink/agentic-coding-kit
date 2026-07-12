# Wiki Initialization and Reinitialization

Use this sequence:

```text
deterministic shallow inventory
-> exactly one Orientation Scout
-> optional consented PR-history collection
-> focused user questions only for consequential unresolved facts
-> one to three targeted Repository Scouts
-> orchestrator synthesis
-> independent evidence review
-> at most one focused correction scan
-> safe managed-section write
-> read-only audit
```

The Orientation Scout reads high-signal repository instructions, maintained
documentation, manifests/workspaces, entry points, CI/release configuration,
test roots, and obvious API/auth/data/IPC/tunnel/job/integration surfaces. It
returns only: what the repository appears to do, major runtimes/workspaces,
important starting paths, critical engineering surfaces, suggested independent
scan axes, and material unknowns. This is temporary context, never a persisted
profile.

Ask the user only when a fact materially changes interpretation and source
cannot establish it, such as whether an experimental application is supported
in production or an undocumented compatibility promise exists.

Choose targeted Scout missions from the orientation evidence. Cover only
applicable axes: runtime/control/data flow and dependency direction; public and
internal interfaces; API clients and external integrations; auth and trust
boundaries; IPC/native bridges/tunnels; jobs, retries, loops and partial
failure; coding/error/configuration/logging conventions; tests/fixtures;
PR/CI/release/deployment practice; and workspace-specific differences. Use one
full scan for a small repository, two independent scans for a medium repository,
and at most three for a large or structurally complex repository.

Every material wiki claim must cite current paths, symbols, manifests, CI,
tests, or verified commands. Source and fresh execution outrank the wiki.

After synthesis and review, write a temporary JSON input under
`.git/agentic-kit/` and pass it to the deterministic helper with
`kit wiki init --synthesis <path>` or `kit wiki reinit --synthesis <path>`:

```json
{
  "schemaVersion": 1,
  "pages": [
    {
      "page": "architecture.md",
      "sections": [
        {
          "heading": "Runtime control flow",
          "body": "A concise reviewed claim about the current repository.",
          "evidence": [
            { "path": "src/main.ts", "symbols": ["main"] }
          ]
        }
      ]
    }
  ]
}
```

The CLI validates page names, tracked evidence paths, referenced symbols,
managed boundaries, links, and page budgets. It appends exact evidence
references itself. It inventories, validates, merges, backs up, and audits; it
does not launch Scouts, reviewers, models, or host sessions.

When PR history is enabled, first run `kit wiki collect-pr-history`, then load
[pr-history.md](pr-history.md) and prepare the synthesis in a separate pass. Historical
lessons use `reviewEvidence` entries containing `provider`, `pullRequest`, and
`threadId`. The CLI verifies those references against the local collection
cache and enforces the acceptance threshold and 20,000-character page budget.

Exclude dependency, vendor, build, coverage, cache, generated output, binary,
and large fixture noise. Profile size by structural complexity, not one magic
threshold. Always create a root wiki. For sufficiently independent workspaces,
non-interactive `auto` uses root plus `.wiki/workspaces/<workspace>.md`; nested
wikis require explicit selection. Root owns shared facts and workspace pages
own local commands/conventions without duplication.

`reinit` repeats orientation, refreshes only kit-managed sections, preserves
human-authored material outside those sections, backs up replaced managed
content under Git metadata, reports conflicts, and removes stale kit-owned
claims/pages only when current evidence no longer justifies them.
