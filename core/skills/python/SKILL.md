---
name: python
description: "Implement or review Python behavior, typing, resources and tests using the project's supported runtime."
---

# Python

Read the applicable repository rules, Python version, packaging configuration and relevant tests first. Keep the existing environment, dependency manager, formatter and type checker. A small code task does not authorize a tooling migration or global installation. Consult installed-version documentation when an API is uncertain.

## Implementation
Use straightforward functions and existing data models. Add a class, protocol or abstraction when the domain, lifecycle or a real integration requires it, not to wrap every operation. Keep public boundaries typed where useful; annotations are not runtime validation. Validate external inputs with the project's established approach rather than assuming an annotated dictionary is trustworthy.

Handle absent values explicitly; avoid shared mutable defaults and hidden process-wide state. Own file, client, connection and transaction cleanup through established context managers or explicit lifetimes. Catch only errors that can be handled meaningfully, preserve diagnostic causes, and never turn an unexpected exception into an empty successful result. Do not catch cancellation or termination just to keep a task appearing successful.

Use asynchronous APIs only where the runtime supports them. Keep blocking work out of async handlers; preserve timeout and cancellation behavior. Bound external work and clean up resources on failure. Do not add retries to non-idempotent operations without a defined policy.

## Evidence
Run the existing targeted tests and configured lint/type checks in the project's environment. Check the relevant malformed-input, exception and cleanup paths, not just successful output. Use deterministic fixtures for time, randomness and external services. Mock actual external boundaries rather than every private helper. Report the interpreter/tooling used and any missing execution environment in the existing result; do not claim a new tool ran because its name appears in documentation.
