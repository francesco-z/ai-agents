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
  | .permissions.ask   = (((.permissions.ask   // []) + ($add[0].permissions.ask // [])) | unique)
  | .permissions.deny  = (((.permissions.deny  // []) + $add[0].permissions.deny ) | unique)
  # Ship the prompt-based "goal" hooks (definition-of-done) globally. These carry
  # no script file, so only the settings keys need merging. We deliberately do NOT
  # merge PreToolUse: that push guard references $CLAUDE_PROJECT_DIR and stays
  # project-scoped. unique keeps re-runs idempotent.
  | .hooks = (.hooks // {})
  | .hooks.Stop         = (((.hooks.Stop         // []) + ($add[0].hooks.Stop         // [])) | unique)
  | .hooks.SubagentStop = (((.hooks.SubagentStop // []) + ($add[0].hooks.SubagentStop // [])) | unique)
' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
echo "    enabled agent teams + merged manual-gate permissions + goal hooks in settings.json"

# ---- Install the shared style/conventions file for every agent, every repo ----
# AGENTS.md is the single source of truth; Claude reads CLAUDE.md, Gemini and
# Antigravity read GEMINI.md/AGENTS.md, Codex reads AGENTS.md. Anything already
# there that we did not write is backed up rather than clobbered.
STYLE_SRC="$REPO_DIR/AGENTS.md"
MARKER="managed-by: francesco-z/ai-agents"

install_style() { # install_style <target-path>
  local target="$1"
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ] && ! grep -q "$MARKER" "$target" 2>/dev/null; then
    cp "$target" "$target.bak"
    echo "    NOTE: backed up your existing $(basename "$target") to $target.bak"
  fi
  cp "$STYLE_SRC" "$target"
  echo "    installed $target"
}

install_style "$DEST/CLAUDE.md"
GEMINI_DEST="${GEMINI_CONFIG_DIR:-$HOME/.gemini}"
install_style "$GEMINI_DEST/GEMINI.md"
install_style "$GEMINI_DEST/AGENTS.md"
install_style "${CODEX_HOME:-$HOME/.codex}/AGENTS.md"

# ---- Put the MCP launchers on PATH for every MCP client ---------------------
# Client configs reference the bare names, so Claude, Codex, Gemini and the rest
# all share one implementation. See mcp/README.md.
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO_DIR/mcp/atlassian/atlassian-mcp.sh" "$HOME/.local/bin/atlassian-mcp"
ln -sf "$REPO_DIR/mcp/github/github-mcp.sh"       "$HOME/.local/bin/github-mcp"
ln -sf "$REPO_DIR/mcp/gitlab/gitlab-mcp.sh"       "$HOME/.local/bin/gitlab-mcp"
ln -sf "$REPO_DIR/mcp/grafana/grafana-mcp.sh"     "$HOME/.local/bin/grafana-mcp"
ln -sf "$REPO_DIR/mcp/kubernetes/kubernetes-mcp.sh" "$HOME/.local/bin/kubernetes-mcp"
echo "    linked ~/.local/bin/{atlassian-mcp,github-mcp,gitlab-mcp,grafana-mcp,kubernetes-mcp}"

# ---- Install the MCP servers each client is ready to use ---------------------
# The configs are checked in at the path each client expects — .claude/mcp.json,
# .gemini/config/mcp_config.json, .codex/config.toml — and installed as-is. Each
# client has its own schema, so the three are maintained side by side; keep them
# in step when you add a server. See mcp/README.md.
CLAUDE_MCP="$SRC/mcp.json"
PROFILE_DIR="${ATLASSIAN_MCP_PROFILE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/atlassian-mcp}"
GITLAB_PROFILE_DIR="${GITLAB_MCP_PROFILE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gitlab-mcp}"
GRAFANA_PROFILE_DIR="${GRAFANA_MCP_PROFILE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/grafana-mcp}"
KUBERNETES_PROFILE_DIR="${KUBERNETES_MCP_PROFILE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/kubernetes-mcp}"

# A launcher-backed server is only installed once its profile exists, so a
# half-configured customer never leaves a server that fails at spawn.
SKIP=""
for name in $(jq -r '.mcpServers | keys[]' "$CLAUDE_MCP"); do
  cmd="$(jq -r --arg n "$name" '.mcpServers[$n].command // ""' "$CLAUDE_MCP")"
  if [ "$cmd" = "atlassian-mcp" ]; then
    profile="$(jq -r --arg n "$name" '.mcpServers[$n].args[0] // ""' "$CLAUDE_MCP")"
    [ -f "$PROFILE_DIR/$profile.env" ] || SKIP="$SKIP $name"
  elif [ "$cmd" = "gitlab-mcp" ]; then
    profile="$(jq -r --arg n "$name" '.mcpServers[$n].args[0] // ""' "$CLAUDE_MCP")"
    [ -f "$GITLAB_PROFILE_DIR/$profile.env" ] || SKIP="$SKIP $name"
  elif [ "$cmd" = "grafana-mcp" ]; then
    profile="$(jq -r --arg n "$name" '.mcpServers[$n].args[0] // ""' "$CLAUDE_MCP")"
    [ -f "$GRAFANA_PROFILE_DIR/$profile.env" ] || SKIP="$SKIP $name"
  elif [ "$cmd" = "kubernetes-mcp" ]; then
    profile="$(jq -r --arg n "$name" '.mcpServers[$n].args[0] // ""' "$CLAUDE_MCP")"
    [ -f "$KUBERNETES_PROFILE_DIR/$profile.env" ] || SKIP="$SKIP $name"
  fi
done

# Claude Code: user scope, one add per server. Re-adding rather than adding
# keeps re-runs idempotent.
if command -v claude >/dev/null 2>&1; then
  for name in $(jq -r '.mcpServers | keys[]' "$CLAUDE_MCP"); do
    case " $SKIP " in
      *" $name "*) echo "    skipped $name (no profile in ${XDG_CONFIG_HOME:-$HOME/.config}/$(jq -r --arg n "$name" '.mcpServers[$n].command' "$CLAUDE_MCP"))"; continue ;;
    esac
    claude mcp remove "$name" -s user >/dev/null 2>&1 || true
    claude mcp add-json -s user "$name" "$(jq -c --arg n "$name" '.mcpServers[$n]' "$CLAUDE_MCP")" >/dev/null 2>&1 \
      && echo "    registered $name (claude, user scope)" \
      || echo "    NOTE: could not register $name at user scope"
  done
else
  echo "    NOTE: 'claude' CLI not on PATH — MCP servers not registered. See mcp/README.md."
fi

# Antigravity / Gemini CLI: merged, not copied, so servers you added by hand survive.
GEM_MCP="${GEMINI_CONFIG_DIR:-$HOME/.gemini}/config/mcp_config.json"
mkdir -p "$(dirname "$GEM_MCP")"
[ -s "$GEM_MCP" ] || echo '{}' > "$GEM_MCP"
TMP="$(mktemp)"
jq --arg skip " $SKIP " --slurpfile add "$REPO_DIR/.gemini/config/mcp_config.json" '
  .mcpServers = ((.mcpServers // {}) + (
    $add[0].mcpServers
    | with_entries(.key as $k | select($skip | contains(" " + $k + " ") | not))))' "$GEM_MCP" > "$TMP"
mv "$TMP" "$GEM_MCP"
echo "    merged $GEM_MCP"

# Codex: TOML has no merge tool, so append once and leave later edits alone.
if [ -d "$HOME/.codex" ] && ! grep -q '^\[mcp_servers\.github\]' "$HOME/.codex/config.toml" 2>/dev/null; then
  cat "$REPO_DIR/.codex/config.toml" >> "$HOME/.codex/config.toml"
  echo "    appended MCP servers to ~/.codex/config.toml"
fi

# ---- Keep agents out of credential directories ------------------------------
# Claude's deny rules ship in .claude/settings.json (merged above). Codex gets a
# permission profile; Antigravity takes absolute paths only, so its rules are
# built from $HOME here. Shell tools (kubectl, aws, ssh, git) keep working for
# Claude and Antigravity; in Codex they need an approved run outside the sandbox.
# The command guardrails (deny/ask) follow the same split: Codex reads
# .codex/rules/ai-agents.rules, Antigravity's are translated from Claude's.
if [ -d "$HOME/.codex" ] && ! grep -q '^\[permissions\.agents-safe\]' "$HOME/.codex/config.toml" 2>/dev/null; then
  TMP="$(mktemp)"
  { grep -q '^default_permissions' "$HOME/.codex/config.toml" 2>/dev/null \
      || { grep '^default_permissions' "$REPO_DIR/.codex/permissions.toml"; echo; }
    cat "$HOME/.codex/config.toml" 2>/dev/null; echo
    sed -n '/^\[permissions\./,$p' "$REPO_DIR/.codex/permissions.toml"; } > "$TMP"
  mv "$TMP" "$HOME/.codex/config.toml"
  echo "    added the agents-safe permission profile to ~/.codex/config.toml"
elif [ -d "$HOME/.codex" ]; then
  # Profile already there: add only the paths introduced since.
  sed -n '/^\[permissions\.agents-safe\.filesystem\]/,$p' "$REPO_DIR/.codex/permissions.toml" \
    | grep '= "deny"$' | while IFS= read -r line; do
      grep -qxF "$line" "$HOME/.codex/config.toml" && continue
      TMP="$(mktemp)"
      awk -v add="$line" '{print} /^\[permissions\.agents-safe\.filesystem\]/{print add}' \
        "$HOME/.codex/config.toml" > "$TMP" && mv "$TMP" "$HOME/.codex/config.toml"
      echo "    added $line to the agents-safe profile"
    done
fi
if [ -d "$HOME/.codex" ]; then
  mkdir -p "$HOME/.codex/rules"
  cp "$REPO_DIR/.codex/rules/ai-agents.rules" "$HOME/.codex/rules/ai-agents.rules"
  echo "    installed ~/.codex/rules/ai-agents.rules"
fi

AGY_SETTINGS="${GEMINI_CONFIG_DIR:-$HOME/.gemini}/antigravity-cli/settings.json"
if [ -f "$AGY_SETTINGS" ]; then
  TMP="$(mktemp)"
  # Bash(...) rules become command(...) prefixes, or regex: when a * sits mid-rule;
  # MCP rules carry over only when they name one tool (no prefix wildcards there).
  jq --arg h "$HOME" --arg run "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
     --slurpfile claude "$SRC/settings.json" '
    def agy:
      if startswith("Bash(") then
        (.[5:-1] | sub("(?<!:):\\*$"; "") | sub(" \\*$"; "")) as $c
        | if ($c | contains("*")) then "command(regex:\($c | gsub("\\*"; ".*")))" else "command(\($c))" end
      elif test("^mcp__[^*]+$") then
        capture("^mcp__(?<s>.+?)__(?<t>.+)$") | "mcp(\(.s)/\(.t))"
      else empty end;
    .permissions = (.permissions // {})
    | .permissions.deny = (((.permissions.deny // [])
        + ([".aws", ".config/atlassian-mcp", ".config/gcloud", ".config/github-mcp",
            ".config/gitlab-mcp", ".config/grafana-mcp", ".config/kubernetes-mcp",
            ".docker/config.json", ".git-credentials", ".gitconfig", ".gnupg", ".kube", ".ssh"]
           | map("read_file(\($h)/\(.))"))
        + ["read_file(\($run)/kubernetes-mcp)", "write_file(/etc)"]
        + ($claude[0].permissions.deny | map(agy))) | unique)
    | .permissions.ask = (((.permissions.ask // [])
        + ($claude[0].permissions.ask | map(agy))) | unique)' \
    "$AGY_SETTINGS" > "$TMP" && mv "$TMP" "$AGY_SETTINGS"
  chmod 600 "$AGY_SETTINGS"
  echo "    merged credential-directory and command guardrails into $AGY_SETTINGS"
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
