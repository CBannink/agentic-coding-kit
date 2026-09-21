---
name: test
description: Test changed behavior through public seams; reproduce a bug or cover a new requirement.
---
# Behavior-level feedback
Start from an acceptance example at the public seam. For a bug, make the relevant failure observable before applying the fix when practical; for new behavior, add one representative failing case, implement that slice, then cover meaningful boundaries. Avoid designing a huge speculative test suite before discovering the actual interface.

Test outcomes, not private call order or incidental internal structure. Mock genuine external boundaries only when appropriate; do not replace the behavior under test. Use repository fixtures and commands before inventing another harness. Include significant failure behavior, not only the successful path.

A red test must fail for the intended reason rather than missing imports, setup failure or unrelated broken infrastructure. A green test shows only what that test exercises. Keep a code check, a user-visible requirement and a performance claim distinct. Report a not-run case as not run.

Once the behavior is established, simplify the touched design without changing the contract. Check relevant neighbors and stop. This is one builder loop, not a separate test-writing team by default.
