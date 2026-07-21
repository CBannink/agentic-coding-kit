# Verification Selection

Fast checks maximize information before model review. Select dynamically:
syntax/format, targeted compile/type, targeted lint, coder-added and nearest
tests, affected build. Behavior changes need executable behavior evidence where
feasible; type/lint alone are insufficient.

Final evidence follows the last relevant edit and may include affected unit,
integration, contract, E2E, type, lint, build, browser, migration dry-run,
artifact consistency, compatibility, packaging, or install checks. Static
inspection alone is sufficient only for non-behavioral changes. If executable
behavior evidence is infeasible, record why and disclose the remaining risk.
Bind results to a commit/tree or clearly described working-tree state. A later
affected edit makes evidence stale.
