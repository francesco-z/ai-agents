#!/usr/bin/env bash
# Read-only GitLab MCP server, launched the same way for every client:
# Claude Code, Codex, Gemini CLI, Cursor, VS Code, Zed.
#
#   gitlab-mcp <profile>
#
# A profile is an env file describing ONE GitLab instance (Cloud or on-prem)
# plus how to reach it. Compatible with GitLab official MCP endpoint
# (introduced in GitLab 18.3+, beta in 18.6+).
set -euo pipefail

PROFILE="${1:-${GITLAB_MCP_PROFILE:-}}"
[ -n "$PROFILE" ] || { echo "usage: $(basename "$0") <profile>" >&2; exit 2; }

SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROFILE_DIR="${GITLAB_MCP_PROFILE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gitlab-mcp}"
ENV_FILE=""
for candidate in "$PROFILE_DIR/$PROFILE.env" "$SELF_DIR/profiles/$PROFILE.env"; do
  [ -f "$candidate" ] && { ENV_FILE="$candidate"; break; }
done
[ -n "$ENV_FILE" ] || { echo "no profile '$PROFILE' in $PROFILE_DIR or $SELF_DIR/profiles" >&2; exit 2; }

set -a; . "$ENV_FILE"; set +a

GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
# Strip trailing slash if present
GITLAB_URL="${GITLAB_URL%/}"

# GitLab MCP endpoint path per official documentation (/api/v4/mcp)
GITLAB_MCP_ENDPOINT="${GITLAB_URL}/api/v4/mcp"

# SOCKS proxy resolution
PROXY=""
if [ -n "${GITLAB_SOCKS_PROXY:-}" ]; then
  case "$GITLAB_SOCKS_PROXY" in
    socks5://*) PROXY="socks5h://${GITLAB_SOCKS_PROXY#socks5://}" ;;
    *)          PROXY="$GITLAB_SOCKS_PROXY" ;;
  esac
fi
NO_PROXY_VAL="${NO_PROXY:-localhost,127.0.0.1,::1}"

if [ -n "$PROXY" ]; then
  export SOCKS_PROXY="$PROXY" ALL_PROXY="$PROXY" all_proxy="$PROXY"
  export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY" http_proxy="$PROXY" https_proxy="$PROXY"
fi
export NO_PROXY="$NO_PROXY_VAL" no_proxy="$NO_PROXY_VAL"

# Optional tool name prefixing (introduced in GitLab 18.11+)
HEADER_ARGS=()
if [ -n "${GITLAB_TOOL_PREFIX:-}" ]; then
  HEADER_ARGS+=(--header "X-Gitlab-Mcp-Server-Tool-Name-Prefix: $GITLAB_TOOL_PREFIX")
fi

# Optional pre-registered OAuth client ID or PAT authorization header
if [ -n "${GITLAB_PERSONAL_TOKEN:-}" ]; then
  HEADER_ARGS+=(--header "Authorization: Bearer $GITLAB_PERSONAL_TOKEN")
fi

IMAGE="${GITLAB_MCP_IMAGE:-docker.io/node:20-alpine}"
case "${GITLAB_MCP_RUNTIME:-podman}" in
  npx)
    exec npx -y mcp-remote "${GITLAB_MCP_ENDPOINT}" ${HEADER_ARGS[@]+"${HEADER_ARGS[@]}"}
    ;;
  podman|docker)
    CONTAINER_BIN="${GITLAB_MCP_RUNTIME:-podman}"
    PROXY_ARGS=()
    if [ -n "$PROXY" ]; then
      PROXY_ARGS=(
        -e "SOCKS_PROXY=$PROXY" -e "ALL_PROXY=$PROXY" -e "all_proxy=$PROXY"
        -e "HTTP_PROXY=$PROXY" -e "HTTPS_PROXY=$PROXY" -e "http_proxy=$PROXY" -e "https_proxy=$PROXY"
      )
    fi
    exec "$CONTAINER_BIN" run --rm -i --network host --env-file "$ENV_FILE" \
      -e "NO_PROXY=$NO_PROXY_VAL" -e "no_proxy=$NO_PROXY_VAL" \
      ${PROXY_ARGS[@]+"${PROXY_ARGS[@]}"} \
      "$IMAGE" \
      npx -y mcp-remote "${GITLAB_MCP_ENDPOINT}" ${HEADER_ARGS[@]+"${HEADER_ARGS[@]}"}
    ;;
  *)
    echo "unknown GITLAB_MCP_RUNTIME='$GITLAB_MCP_RUNTIME' (podman|docker|npx)" >&2; exit 2 ;;
esac
