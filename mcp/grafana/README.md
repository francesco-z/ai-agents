# Grafana MCP server

Launcher and profiles for the official [Grafana MCP server](https://github.com/grafana/mcp-grafana)
(`mcp-grafana`), read-only. For a shared, remote deployment on Kubernetes see
[`helm/`](helm/README.md).

| Server | Reaches | Transport | Secrets from |
| --- | --- | --- | --- |
| `grafana_onprem` | Self-hosted Grafana, incl. behind a VPN | stdio launcher (`grafana-mcp`) | `~/.config/grafana-mcp/onprem.env` |
| `grafana_cloud` | Grafana **Cloud** stack (`*.grafana.net`) | stdio launcher (`grafana-mcp`) | `~/.config/grafana-mcp/cloud.env` |
| `grafana_remote` | A shared server deployed with [`helm/`](helm/README.md) | streamable HTTP | `$GRAFANA_MCP_SERVER_TOKEN` |

## How it works

There is no MCP endpoint on the Grafana side: `mcp-grafana` is the local process
your client spawns, and it turns tool calls into Grafana HTTP API calls using a
service account token. Cloud and on-prem differ only in `GRAFANA_URL`, so one
profile format and one tool vocabulary cover both.

- **Default runtime**: `podman`, running `docker.io/grafana/mcp-grafana` as in
  [Grafana's Docker setup](https://grafana.com/docs/grafana-cloud/ai-tools/mcp-servers/oss-mcp/set-up/install-with-docker/)
  (`run --rm -i … -t stdio`). `GRAFANA_MCP_RUNTIME=uvx` runs the PyPI package
  instead (`uvx mcp-grafana`), `docker` works like `podman`. The version comes
  from `MCP_GRAFANA_VERSION=` (image tag / package version, default `1.3.0`);
  `GRAFANA_MCP_IMAGE=` overrides the whole image.
- **SOCKS5 / VPN**: `GRAFANA_SOCKS5_PROXY=socks5://localhost:9999` is native to
  `mcp-grafana` and scoped to its Grafana traffic. Containers run with
  `--network host`, so the tunnel on `localhost` is reachable.
- **Org**: `GRAFANA_ORG_ID` selects the organization (sent as `X-Grafana-Org-Id`).

## Version pin

The launcher defaults to **1.3.0**. From 1.4.0 the server speaks MCP
`2026-07-28`, and its stdio transport stops answering after the client opens
`subscriptions/listen` (mark3labs/mcp-go#976). Claude Code does that
right after connecting, so it shows `connected · tools fetch failed` (tools/list
times out). 1.3.0 has no `server/discover`, so clients fall back to the
`2025-11-25` handshake. Drop the pin once a release includes
grafana/mcp-grafana#1236 (mcp-go v1.1.1). To run a newer build meanwhile, start
Claude Code with `MCP_PROTOCOL_NEGOTIATION=legacy` — that downgrades *every* MCP
server, not just this one.

The remote server in [`helm/`](helm/README.md) is unaffected: the bug is in
the stdio transport only.

## Read-only, in three layers

1. **The service account** has the Viewer role. Nothing below matters if this is wrong.
2. **`--disable-write`**, forced by the launcher regardless of the profile: write
   tools are never advertised. `GRAFANA_MCP_EXTRA_ARGS` can only add flags
   (e.g. `--disable-admin --disable-oncall`), not remove this one.
3. **Client permissions** — `.claude/settings.json` allows the read prefixes and
   denies the write ones for `grafana_onprem`, `grafana_cloud` and
   `grafana_remote`; Gemini's equivalent is `excludeTools`. Codex has no
   per-tool allowlist — there, layers 1–2 are the boundary.

`alerting_manage_*` and `grafana_api_request` are neither allowed nor denied, so
Claude Code prompts for them: they multiplex several operations behind one name.

## Setup

```bash
mkdir -p ~/.config/grafana-mcp
cp mcp/grafana/profiles/onprem.env.example ~/.config/grafana-mcp/onprem.env
chmod 600 ~/.config/grafana-mcp/onprem.env   # it holds the token
$EDITOR ~/.config/grafana-mcp/onprem.env
make install
```

The profile filename must match the server's `args` (`onprem`, `cloud`). For a
second instance, add a server to all three client configs — say
`grafana_globex` with `args: ["globex"]` — and a `globex.env` beside it. Keep
the `grafana_` prefix and add matching rules to `.claude/settings.json`.

Smoke test without a client:

```bash
grafana-mcp onprem   # logs "Starting Grafana MCP server using stdio transport"; Ctrl-C to stop
```
