#!/usr/bin/env bash
# Read-only Grafana MCP server, launched the same way for every client:
# Claude Code, Codex, Gemini CLI, Cursor, VS Code, Zed.
#
#   grafana-mcp <profile>
#
# A profile is an env file describing ONE Grafana instance (Cloud or on-prem)
# plus how to reach it. Read-only is enforced here — by the server's own
# --disable-write — so it does not depend on the model behaving.
set -euo pipefail

PROFILE="${1:-${GRAFANA_MCP_PROFILE:-}}"
[ -n "$PROFILE" ] || { echo "usage: $(basename "$0") <profile>" >&2; exit 2; }

SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROFILE_DIR="${GRAFANA_MCP_PROFILE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/grafana-mcp}"
ENV_FILE=""
for candidate in "$PROFILE_DIR/$PROFILE.env" "$SELF_DIR/profiles/$PROFILE.env"; do
  [ -f "$candidate" ] && { ENV_FILE="$candidate"; break; }
done
[ -n "$ENV_FILE" ] || { echo "no profile '$PROFILE' in $PROFILE_DIR or $SELF_DIR/profiles" >&2; exit 2; }

set -a; . "$ENV_FILE"; set +a

[ -n "${GRAFANA_URL:-}" ] || { echo "$ENV_FILE does not set GRAFANA_URL" >&2; exit 2; }

# Forced regardless of the profile: write tools are never advertised at all.
# GRAFANA_MCP_EXTRA_ARGS can only narrow further (e.g. --disable-admin).
ARGS=(--disable-write)
# shellcheck disable=SC2206  # word splitting of the flag list is intended
[ -n "${GRAFANA_MCP_EXTRA_ARGS:-}" ] && ARGS+=(${GRAFANA_MCP_EXTRA_ARGS})

# 1.4.0+ speaks MCP 2026-07-28, whose stdio transport deadlocks after
# subscriptions/listen (grafana/mcp-grafana#1236), so Claude Code times out on
# tools/list. 1.3.0 predates it and makes clients fall back to initialize.
# Drop the pin once a release ships mcp-go >= v1.1.1.
MCP_GRAFANA_VERSION="${MCP_GRAFANA_VERSION:-1.3.0}"
IMAGE="${GRAFANA_MCP_IMAGE:-docker.io/grafana/mcp-grafana:$MCP_GRAFANA_VERSION}"
RUNTIME="${GRAFANA_MCP_RUNTIME:-podman}"
case "$RUNTIME" in
  uvx)
    exec uvx --from "mcp-grafana${MCP_GRAFANA_VERSION:+==$MCP_GRAFANA_VERSION}" mcp-grafana "${ARGS[@]}"
    ;;
  podman|docker)
    # The image entrypoint defaults to SSE on :8000; -t stdio overrides it, as in
    # Grafana's own Docker instructions. --network host so a SOCKS tunnel on
    # localhost (GRAFANA_SOCKS5_PROXY) is reachable from the container.
    exec "$RUNTIME" run --rm -i --network host --env-file "$ENV_FILE" \
      "$IMAGE" -t stdio "${ARGS[@]}"
    ;;
  *)
    echo "unknown GRAFANA_MCP_RUNTIME='$RUNTIME' (podman|docker|uvx)" >&2; exit 2 ;;
esac
