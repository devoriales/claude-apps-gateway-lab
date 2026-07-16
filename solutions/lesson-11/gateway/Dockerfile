# Debian 12 (bookworm) is a supported OS for the native claude installer and
# uses glibc, avoiding the extra musl/Alpine dependency steps the installer
# needs on Alpine. See VERSION_MANIFEST.md for the pinned CLAUDE_VERSION.
FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash gateway

USER gateway
WORKDIR /home/gateway

ARG CLAUDE_VERSION=2.1.207
RUN curl -fsSL https://claude.ai/install.sh | bash -s ${CLAUDE_VERSION}

ENV PATH="/home/gateway/.local/bin:${PATH}"

# Fails the build if the installed binary can't run in this container.
RUN claude --version

EXPOSE 8080

# gateway.yaml is bind-mounted at runtime (see docker-compose.yml), not baked
# into the image, so students can edit config without rebuilding.
ENTRYPOINT ["claude", "gateway", "--config", "/etc/claude/gateway.yaml"]
