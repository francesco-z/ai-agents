#!/usr/bin/env bash
# Install the agent team, skills, and workflows from this repo into your
# user-level Claude Code config (~/.claude) so they work in ALL your repos.
# Idempotent: safe to re-run after pulling updates.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/.claude"
DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required."; exit 1; }

echo "==> Installing into $DEST"
mkdir -p "$DEST/agents" "$DEST/skills" "$DEST/workflows"

sync() { # sync <subdir>
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$SRC/$1/" "$DEST/$1/"
  else
    cp -R "$SRC/$1/." "$DEST/$1/"
  fi
  echo "    synced $1/"
}
sync agents
sync skills
sync workflows

# ---- Merge env flag + manual-gate permissions into ~/.claude/settings.json ----
SETTINGS="$DEST/settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
TMP="$(mktemp)"
jq --slurpfile add "$SRC/settings.json" '
    .env = ((.env // {}) + $add[0].env)
  | .permissions = (.permissions // {})
  | .permissions.allow = (((.permissions.allow // []) + $add[0].permissions.allow) | unique)
  | .permissions.deny  = (((.permissions.deny  // []) + $add[0].permissions.deny ) | unique)
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
echo "    enabled agent teams + merged manual-gate permissions in settings.json"

# ---- Register the GitHub MCP server at USER scope (token sourced at runtime) ----
# Note: `claude mcp list` is cwd-sensitive (it includes project .mcp.json), so we
# force a user-scope add and tolerate "already exists" on re-runs.
if command -v claude >/dev/null 2>&1; then
  GH_JSON='{"type":"http","url":"https://api.githubcopilot.com/mcp/","headers":{"Authorization":"Bearer ${GITHUB_MCP_TOKEN}"}}'
  if claude mcp add-json -s user github "$GH_JSON" 2>/dev/null; then
    echo "    registered github MCP (user scope)"
  else
    claude mcp remove github -s user >/dev/null 2>&1 \
      && claude mcp add-json -s user github "$GH_JSON" >/dev/null 2>&1 \
      && echo "    re-registered github MCP (user scope)" \
      || echo "    NOTE: github MCP add reported it already exists at user scope (ok)"
  fi
else
  echo "    NOTE: 'claude' CLI not on PATH — github MCP not registered. See README."
fi

cat <<'EOF'

==> Done.

Two things to finish setup:

1) Make the GitHub MCP token available to your shell (it is read at runtime,
   never stored). Add this to ~/.bashrc or ~/.zshrc:

       export GITHUB_MCP_TOKEN="$(gh auth token)"

2) Agent teams are experimental and opt-in. They are now enabled globally via
   CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 in ~/.claude/settings.json. If you
   prefer an env var instead, add to your shell profile:

       export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

Restart Claude Code (or start a new session) to pick up the agents.
Verify with:  /agents   ·   /skills   ·   type / to see /multi-repo-feature and /troubleshoot-fanout
EOF
