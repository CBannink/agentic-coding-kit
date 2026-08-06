# Context and Repository Knowledge

ACK does not create a durable session-memory runtime.

The active host primary owns the working context. It keeps a compact in-context
map of:

- the current goal and acceptance criteria;
- consequential decisions and preserve constraints;
- active plan nodes and changed paths;
- fresh evidence, findings, and failure signatures.

Long logs, transcripts, completed exploration, private reasoning, and ordinary
task notes are not written to repository memory files. Harness-native session
resumption or compaction remains the host's responsibility.

## Repository knowledge

`.wiki` is the only ACK repository-knowledge surface. It contains curated,
progressively disclosed facts about ownership, vertical flows, coding
conventions, tests, commands, and proof. Every synthesized claim is tied to
tracked source and optional symbols; audit reports drift.

The wiki is updated only through explicit `wiki init` or `wiki reinit`. Normal
Build, Design, Analyze, and Review work reads the smallest useful section and
reports drift instead of rewriting knowledge.

Do not restore `.kit/context`, `.kit/session-state`, handoff logs, reflection
files, cross-repository skill memory, or goal-workflow state. Reusable procedure
belongs in a skill; stable repository fact belongs in `.wiki`; active task state
stays in the primary context.
