FROM debian:trixie-slim

# Match these to your host user if you bind-mount config/state on Linux.
ARG UID=1000
ARG GID=1000
# Claude Code version for the native installer (an exact version, stable or
# latest). Pinned to the version the read-scope setting used by the scripts
# (permissions.blockReadsOutsideWorkingDirectories) was tested with.
ARG CLAUDE_CODE_VERSION=2.1.322

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl gawk gh git jq sqlite3 \
 && rm -rf /var/lib/apt/lists/*

RUN groupadd -g "$GID" reviewer && useradd -m -u "$UID" -g "$GID" -s /bin/bash reviewer

USER reviewer
WORKDIR /home/reviewer
# The image is rebuilt to update; no background self-updates inside the container.
ENV DISABLE_AUTOUPDATER=1 \
    PATH=/home/reviewer/.local/bin:/usr/local/bin:/usr/bin:/bin

# Official native installer, installs to ~/.local/bin/claude.
RUN curl -fsSL https://claude.ai/install.sh | bash -s "$CLAUDE_CODE_VERSION" \
 && claude --version

# Pre-create the mount points so named volumes inherit the non-root owner.
RUN mkdir -p .config/auto-pr-review .local/state/auto-pr-review

COPY --chown=reviewer:reviewer bin/ /opt/claude-pr-reviewer/bin/
COPY --chown=reviewer:reviewer config/ /opt/claude-pr-reviewer/config/
COPY --chown=reviewer:reviewer install.sh /opt/claude-pr-reviewer/
COPY --chown=reviewer:reviewer docker/entrypoint.sh /opt/claude-pr-reviewer/docker/

ENTRYPOINT ["/opt/claude-pr-reviewer/docker/entrypoint.sh"]
