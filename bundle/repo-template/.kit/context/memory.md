# Repo Memory

Durable repo facts only.

## Session Handoff Index

Scan this table on startup — it is the ONLY session-related content loaded automatically.
**Do NOT load handoff files on startup.** Read a handoff path only when the summary signals relevance.
**Max 20 rows. Most recent first. Drop oldest when full. Use `handoff-register.ps1` to append.**

| Date | Task | What you'll find there (≤15 words) | Handoff path |
|------|------|-------------------------------------|--------------|
