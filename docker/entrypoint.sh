#!/usr/bin/env bash
# entrypoint.sh -- friendly first-time banner + pass-through to whatever you ran.
#
# If the container is started without explicit args, drops you in bash with
# a quick orientation. If args are passed (e.g. `docker run ... opencode`),
# they're executed verbatim.

set -e

if [[ "${SUPPRESS_BANNER:-0}" != "1" ]]; then
    cat <<'BANNER'

╔══════════════════════════════════════════════════════════════════╗
║  Caspar Bannink Agentic Coding Kit -- container ready            ║
╚══════════════════════════════════════════════════════════════════╝

  workspace      mount your project to /workspace
  installed at   ~/.agents/  (tools, skills, context)
  CLIs           opencode, pwsh
  helpers        pwsh ~/.agents/tools/doctor.ps1   (verify install)
                 opencode auth                     (configure provider)
                 opencode                          (start REPL)

  Free-tier hint: opencode supports OpenRouter free models -- pick one in
                  `opencode auth` if you don't have a paid API key yet.

BANNER
fi

# Suppress banner on subsequent invocations within the same TTY
export SUPPRESS_BANNER=1

exec "$@"
