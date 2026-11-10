#!/usr/bin/env bash
# Container entrypoint: install the scripts and seed ~/.config/auto-pr-review
# (existing files are never overwritten), then either run the given command
# once or run a tick every INTERVAL_SECONDS.
set -euo pipefail

# Blank lines in .env arrive as empty variables; gh and claude would treat
# them as set.
for v in ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN GH_TOKEN; do
  [[ -n "${!v:-}" ]] || unset "$v"
done

/opt/claude-pr-reviewer/install.sh

if (( $# > 0 )); then exec "$@"; fi

while true; do
  auto-review-prs.sh || echo "tick exited with status $?" >&2
  sleep "${INTERVAL_SECONDS:-300}"
done
