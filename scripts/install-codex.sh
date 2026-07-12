#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/cli/dist/kit.cjs"
if [[ -f "$BUNDLE" ]]; then exec node "$BUNDLE" install --host codex "$@"; fi
exec node "$ROOT/cli/node_modules/tsx/dist/cli.mjs" "$ROOT/cli/src/index.ts" install --host codex "$@"
