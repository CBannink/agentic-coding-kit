---
name: review
description: "Use when the user asks to review, audit, check quality, or find bugs in code. Runs one unified reviewer by default plus conditional security review."
---

# /review

Review the requested diff or code with one default reviewer:

- `code-quality-reviewer` for normal code review and audit.
- `security-reviewer` only when trust-boundary risk is present.

Trust-boundary triggers: auth/authz, secrets, crypto, permissions, untrusted
input, external HTTP, DB writes, filesystem paths, command execution, payments,
or sensitive data exposure.

The unified reviewer covers correctness bugs, architecture mismatch,
over-abstraction, misplaced files, duplicate logic, AI slop, weak tests, and
maintainability regressions.

Load `silent-failure-hunter` on demand when the diff adds or changes async
work, try/catch, fallbacks, CLI exit handling, logging, filesystem/network, or
subprocess paths. Treat it as a focused review lens, not a default reviewer.

False-positive-check every BLOCKING finding by reading the cited file and nearby
code before presenting it.

Do not run multi-pass review, legacy verifier agents, writeback gates,
reflection gates, or memory maintenance by default.
