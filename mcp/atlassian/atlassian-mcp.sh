#!/usr/bin/env bash
# Read-only Atlassian (Confluence + Jira) MCP server, launched the same way for
# every client: Claude Code, Codex, Gemini CLI, Cursor, VS Code, Zed.
#
#   atlassian-mcp <profile>
#
# A profile is an env file describing ONE Atlassian instance (Cloud or
# Server/Data Center) plus how to reach it. Read-only is enforced here — by the
# server's own tool filter — so it does not depend on the model behaving.
set -euo pipefail

PROFILE="${1:-${ATLASSIAN_MCP_PROFILE:-}}"
[ -n "$PROFILE" ] || { echo "usage: $(basename "$0") <profile>" >&2; exit 2; }

SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROFILE_DIR="${ATLASSIAN_MCP_PROFILE_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/atlassian-mcp}"
ENV_FILE=""
for candidate in "$PROFILE_DIR/$PROFILE.env" "$SELF_DIR/profiles/$PROFILE.env"; do
  [ -f "$candidate" ] && { ENV_FILE="$candidate"; break; }
done
[ -n "$ENV_FILE" ] || { echo "no profile '$PROFILE' in $PROFILE_DIR or $SELF_DIR/profiles" >&2; exit 2; }

set -a; . "$ENV_FILE"; set +a

# ---- Boundary 1: only read tools are exposed to the model at all -------------
# Tool names are identical on Cloud and Server/DC, so one list covers both.
READONLY_TOOLS="\
confluence_search,confluence_get_page,confluence_get_page_children,\
confluence_get_space_page_tree,confluence_get_page_history,confluence_get_comments,\
confluence_get_labels,confluence_get_attachments,confluence_download_attachment,\
confluence_search_user,\
jira_search,jira_get_issue,jira_get_project_issues,jira_search_fields,\
jira_get_transitions,jira_get_all_projects,jira_search_projects,\
jira_get_project_versions,jira_get_project_components,jira_get_agile_boards,\
jira_get_board_issues,jira_get_sprints_from_board,jira_get_sprint_issues,\
jira_get_link_types,jira_get_worklog,jira_get_user_profile,\
jira_batch_get_changelogs,jira_download_attachments"

export ENABLED_TOOLS="${ENABLED_TOOLS:-$READONLY_TOOLS}"
export READ_ONLY_MODE=true   # second latch: mutating calls are refused even if enabled

# ---- VPN: force remote DNS so the private hostname resolves inside the tunnel -
if [ -n "${ATLASSIAN_SOCKS_PROXY:-}" ]; then
  case "$ATLASSIAN_SOCKS_PROXY" in
    socks5://*) PROXY="socks5h://${ATLASSIAN_SOCKS_PROXY#socks5://}" ;;
    *)          PROXY="$ATLASSIAN_SOCKS_PROXY" ;;
  esac
  export SOCKS_PROXY="$PROXY" ALL_PROXY="$PROXY" all_proxy="$PROXY"
  export HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY" http_proxy="$PROXY" https_proxy="$PROXY"
fi
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,::1}" no_proxy="${NO_PROXY:-localhost,127.0.0.1,::1}"

[ -n "${CONFLUENCE_URL:-}${JIRA_URL:-}" ] || { echo "$ENV_FILE sets neither CONFLUENCE_URL nor JIRA_URL" >&2; exit 2; }

PKG="mcp-atlassian${MCP_ATLASSIAN_VERSION:+==$MCP_ATLASSIAN_VERSION}"
case "${ATLASSIAN_MCP_RUNTIME:-uvx}" in
  uvx)
    EXTRA=()
    [ -n "${ATLASSIAN_SOCKS_PROXY:-}" ] && EXTRA+=(--with "requests[socks]")
    exec uvx ${EXTRA[@]+"${EXTRA[@]}"} --from "$PKG" mcp-atlassian
    ;;
  docker)
    # --network host so a SOCKS tunnel on localhost is reachable from the container.
    exec docker run --rm -i --network host --env-file "$ENV_FILE" \
      -e READ_ONLY_MODE -e ENABLED_TOOLS \
      -e SOCKS_PROXY -e ALL_PROXY -e HTTP_PROXY -e HTTPS_PROXY -e NO_PROXY \
      "ghcr.io/sooperset/mcp-atlassian:${MCP_ATLASSIAN_VERSION:-latest}"
    ;;
  *)
    echo "unknown ATLASSIAN_MCP_RUNTIME='$ATLASSIAN_MCP_RUNTIME' (uvx|docker)" >&2; exit 2 ;;
esac
