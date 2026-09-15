# GitHub MCP server

Official remote GitHub MCP (issues, PRs, code search).

| Server | Reaches | Transport | Secrets from |
| --- | --- | --- | --- |
| `github` | github.com | HTTPS (stdio bridge on Codex/Antigravity) | `$GITHUB_MCP_TOKEN` |

## Transport

Remote servers become a `mcp-remote` stdio bridge (`github-mcp.sh`) on Antigravity and Codex —
that works on every build, instead of betting on which remote-URL key a given
version accepts. Claude Code keeps native HTTP.

## Auth

Tokens come from the environment (`$GITHUB_MCP_TOKEN`).

Add to your shell profile:

```bash
export GITHUB_MCP_TOKEN="$(gh auth token)"
```
