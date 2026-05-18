---
name: memory-review
description: >
  Review and manage the memory inbox -- approve or reject patterns the agent learned
  during sessions. Use when the user types /memory-review or asks to review what the
  agent learned, or to see pending inbox entries.
---

# /memory-review

Show the user their memory inbox and let them approve or reject learned patterns.

## What this skill does

The memory inbox collects patterns the agent observed during sessions:
- Patterns seen 2+ times in reflections.md (additive class)
- Successfully applied prompt improvements
- Repo-specific observations from workflow-evidence (verification commands, skipped reviewers)
- Patterns auto-promoted by auto-consolidate

Each pattern is held in `~/.agents/context/memory-inbox.md` as a numbered entry
until the developer explicitly approves or rejects it. Approved entries are appended
to their suggested target file. Nothing is applied automatically.

---

## Execution steps

### Step 1 -- Query the inbox

```powershell
pwsh ~/.agents/tools/memory-inbox.ps1 -Action list -Json
```

### Step 2 -- Handle empty inbox

If `pending` is 0, tell the user:

> Memory inbox is empty -- no new patterns to review.

Then stop. Do not invent entries.

### Step 3 -- Present pending entries

For each pending entry, show:

| Field | Value |
|-------|-------|
| ID | `INBOX-001` |
| Learned from | Source field (e.g., "reflections.md (seen 3x)") |
| Pattern | What was learned |
| Would be written to | Suggested target file |

Group them clearly. Example format:

```
INBOX-001 (2026-05-15)
  Learned from: reflections.md (seen 3x)
  Pattern:      Always run security reviewer for auth-related changes in this repo
  Target:       .kit/context/memory.md

INBOX-002 (2026-05-15)
  Learned from: prompt-improvements.md (applied)
  Pattern:      Prefer imperative mood in commit messages
  Target:       ~/.agents/instructions.md
```

### Step 4 -- Ask the user

Ask which entries to approve or reject. Accept:
- "approve all" / "approve INBOX-001 INBOX-003"
- "reject INBOX-002" / "reject INBOX-002 not relevant"
- A mix: "approve 1, reject 2"

Do NOT auto-approve anything. Wait for explicit user response.

### Step 5 -- Apply decisions

For each approval:
```powershell
pwsh ~/.agents/tools/memory-inbox.ps1 -Action approve -EntryId "INBOX-001"
```

For each rejection (include reason when the user gave one):
```powershell
pwsh ~/.agents/tools/memory-inbox.ps1 -Action reject -EntryId "INBOX-002" -Reason "not applicable to this repo"
```

For "approve all":
```powershell
pwsh ~/.agents/tools/memory-inbox.ps1 -Action approve -EntryId "all"
```

### Step 6 -- Show summary

Tell the user what was applied and where. Example:

> Applied 2 patterns:
> - INBOX-001 --> .kit/context/memory.md
> - INBOX-003 --> ~/.agents/instructions.md
>
> Rejected 1 pattern:
> - INBOX-002 (not applicable to this repo)

---

## Maintenance commands (mention to user if asked)

```powershell
# Collect new patterns from current session artifacts
pwsh ~/.agents/tools/memory-inbox.ps1 -Action collect

# Remove approved/rejected entries older than 30 days
pwsh ~/.agents/tools/memory-inbox.ps1 -Action flush

# Machine-readable dump of all entries
pwsh ~/.agents/tools/memory-inbox.ps1 -Action list -Json
```

---

## Do not

- Auto-approve entries the user has not explicitly confirmed
- Invent entries not present in the inbox file
- Edit `.kit/context/memory.md` or `~/.agents/instructions.md` directly -- always go through the tool so the inbox audit trail stays consistent
- Run collect automatically during /memory-review -- collect runs at post-session; /memory-review is for reviewing what was already collected
