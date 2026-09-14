#!/usr/bin/env bash
# stdio bridge to GitHub's remote MCP server, for clients that cannot do HTTP
# transport or cannot expand ${GITHUB_MCP_TOKEN} in their own config (Codex).
# Clients that can — Claude Code — get the http transport instead and skip this
# hop; see mcp/README.md.
set -euo pipefail

[ -n "${GITHUB_MCP_TOKEN:-}" ] || {
  echo "GITHUB_MCP_TOKEN is unset. Add to your shell profile:" >&2
  echo '  export GITHUB_MCP_TOKEN="$(gh auth token)"' >&2
  exit 2
}

exec npx -y mcp-remote https://api.githubcopilot.com/mcp/ \
  --header "Authorization: Bearer $GITHUB_MCP_TOKEN"
