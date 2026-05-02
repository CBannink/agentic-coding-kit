# Caspar Bannink Agentic Coding Kit -- single-image runtime.
#
# Includes: pwsh 7, Python 3 + playwright + pyyaml, Node + OpenCode CLI,
# the kit installed device-wide for the container's HOME (/root by default).
#
# Build:
#   docker build -t agentic-kit:latest .
#
# Run interactively (mount your project, pass API keys):
#   docker run -it --rm \
#     -v "$PWD:/workspace" \
#     -e KIMI_API_KEY=$KIMI_API_KEY \
#     -e OPENROUTER_API_KEY=$OPENROUTER_API_KEY \
#     agentic-kit:latest
#
# Inside the container:
#   cd /workspace
#   opencode auth        # configure provider once
#   opencode             # start the REPL
#   pwsh ~/.agents/tools/doctor.ps1     # verify install

FROM mcr.microsoft.com/powershell:lts-7.4-ubuntu-22.04

ENV DEBIAN_FRONTEND=noninteractive \
    AGENTS_HOME=/root/.agents \
    AGENTS_SESSION_ROOT=/root/.agents/session-state

# Base utilities + Python + Node
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git build-essential \
        python3 python3-pip python3-venv \
        nodejs npm \
        ripgrep jq \
        imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Python deps for design loop (playwright + pyyaml)
# Browsers installed at build time so the runner is ready out of the box.
RUN python3 -m pip install --no-cache-dir --break-system-packages \
        playwright pyyaml \
    && python3 -m playwright install chromium --with-deps

# OpenCode CLI globally
RUN npm install -g opencode-ai

# Kit
WORKDIR /opt/agentic-kit
COPY . .

# Strip CRLF that Windows authoring may have introduced
RUN find ./bundle ./scripts -type f \( -name "*.ps1" -o -name "*.sh" -o -name "*.json" -o -name "*.md" \) \
        -exec sed -i 's/\r$//' {} \; \
    && chmod +x ./scripts/install.sh \
    && chmod +x ./bundle/global/.agents/tools/*.ps1 || true

# Install kit device-wide for the container's root user
RUN pwsh -NoProfile -File ./scripts/install.ps1 \
        -HomeRoot /root \
        -DeviceWide all \
        -Force

# Quick install check at build time -- fails the build if validator finds errors
RUN pwsh -NoProfile -File ./scripts/validate-bundle.ps1 || (echo "validate-bundle FAILED" && exit 1)

# Default workspace (volume-mount your project here)
WORKDIR /workspace

# Helpful default env for ad-hoc usage
ENV PATH="/usr/local/bin:/root/.npm-global/bin:${PATH}" \
    AGENTS_PYTHON=python3

# Copy the doctor + a quick-start banner into a tiny entrypoint
COPY docker/entrypoint.sh /usr/local/bin/agentic-kit-entrypoint
RUN chmod +x /usr/local/bin/agentic-kit-entrypoint

ENTRYPOINT ["/usr/local/bin/agentic-kit-entrypoint"]
CMD ["bash"]
