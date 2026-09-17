# GitLab MCP server

Launcher and configuration for the official [GitLab Model Context Protocol (MCP) server](https://docs.gitlab.com/user/model_context_protocol/mcp_server/).

| Server | Reaches | Transport | Secrets from |
| --- | --- | --- | --- |
| `gitlab_onprem` | GitLab **Self-Managed / On-Prem**, incl. behind a VPN | stdio launcher (`gitlab-mcp`) | `~/.config/gitlab-mcp/onprem.env` |
| `gitlab_cloud` | GitLab **Cloud** (`gitlab.com`) | stdio launcher (`gitlab-mcp`) | `~/.config/gitlab-mcp/cloud.env` |

## How it works

The launcher connects to the official GitLab MCP endpoint (`/api/v4/mcp`) using `mcp-remote`.

- **On-Prem & Cloud unified**: Uses the same launcher and profile structure.
- **Upgrades & Version Independence**: GitLab introduced native MCP support at `/api/v4/mcp` (experiment in 18.3, beta in 18.6+, default tool prefixing in 18.11). On 17.3, OAuth Dynamic Client Registration exists; as soon as the instance upgrades to 18.x+, the endpoint works seamlessly without client-side reconfiguration.
- **SOCKS5 / VPN Support**: `GITLAB_SOCKS_PROXY=socks5://localhost:9999` is automatically converted to `socks5h://` so hostnames resolve inside the tunnel.
- **Tool Prefixing**: Set `GITLAB_TOOL_PREFIX=gitlab_` to avoid conflicts with other tools.

## Setup

```bash
mkdir -p ~/.config/gitlab-mcp
cp mcp/gitlab/profiles/onprem.env.example ~/.config/gitlab-mcp/onprem.env
chmod 600 ~/.config/gitlab-mcp/onprem.env
$EDITOR ~/.config/gitlab-mcp/onprem.env
make install
```
