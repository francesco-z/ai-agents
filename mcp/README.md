# MCP servers, vendor-neutral

```text
.claude/mcp.json              ← ready-to-use config, one per client, at the path
.gemini/config/mcp_config.json   that client expects; install.sh copies them in
.codex/config.toml
mcp/
├── atlassian/            ← launcher + profile examples (read-only Confluence/Jira)
└── github/               ← launcher (stdio bridge for clients without HTTP)
```

| Server | Reaches | Transport | Secrets from |
| --- | --- | --- | --- |
| `github` | github.com | HTTPS (stdio bridge on Codex/Antigravity) | `$GITHUB_MCP_TOKEN` |
| `atlassian_dc` | Confluence/Jira **Server or Data Center**, incl. behind a VPN | stdio launcher | `~/.config/atlassian-mcp/onprem.env` |
| `atlassian_cloud` | Atlassian **Cloud**, via the same self-hosted server | stdio launcher | `~/.config/atlassian-mcp/cloud.env` |
| `atlassian_rovo` | Atlassian **Cloud**, via Atlassian's official Rovo MCP | HTTPS, OAuth 2.1 | Atlassian's own login |

## One config per client

There is no cross-vendor MCP config file — each client reads its own, and the
schemas differ enough that one file cannot serve all of them. So each is checked
in ready to use, at the path that client expects, and maintained by hand:

| Repo file | Installed to | Shape it needs | How |
| --- | --- | --- | --- |
| `.claude/mcp.json` | `~/.claude.json`, user scope | `"type": "http"` + `"url"`, or `"command"` + `"args"` | one `claude mcp add-json -s user` per server |
| `.gemini/config/mcp_config.json` | same path under `~` | stdio only, plus `excludeTools` | `jq` merge, so hand-added servers survive |
| `.codex/config.toml` | `~/.codex/config.toml` | stdio only, TOML | appended once, only if `~/.codex` exists |
| — | Cursor, VS Code, Zed | same shape as Claude Code | copy `.claude/mcp.json` |

**Adding a server means editing all three.** That is the cost of keeping them
readable and copy-able instead of generated.

Remote servers become a `mcp-remote` stdio bridge on Antigravity and Codex —
that works on every build, instead of betting on which remote-URL key a given
version accepts. Claude Code keeps native HTTP.

Everything is registered at **user scope**, so there is no project `.mcp.json` in
this repo — it would only duplicate the user-scope `github` entry for sessions
started here. For Claude and Gemini, a launcher-backed server is skipped until
its profile exists in `~/.config/atlassian-mcp/`, so a half-configured customer
never registers a server that fails at spawn; Codex is a verbatim append, so
prune those blocks yourself.

Two rules keep the rest portable:

1. **No secrets in a committed config.** Tokens come from the environment
   (`$GITHUB_MCP_TOKEN`) or a `chmod 600` profile file outside the repo.
2. **Anything with logic goes in a launcher on `PATH`**, not in client config —
   proxies, read-only enforcement, auth selection, header injection. Every
   client can spawn a command; almost none can express those. `install.sh` links
   the launchers into `~/.local/bin`, so all clients share one implementation and
   a fix lands everywhere at once.

---

# Atlassian: read-only Confluence + Jira

One command, one profile format, every client. Works against Server/Data Center
behind a SOCKS5 tunnel and against Cloud, without the agent being able to write
anything.

## Which backend for which instance

| Instance | Use | Why |
| --- | --- | --- |
| Cloud | `atlassian_rovo` | First-party, OAuth 2.1, respects your Atlassian permissions |
| Cloud | or `atlassian_cloud` | Same tool names as your on-prem sites — one vocabulary everywhere |
| Server / Data Center | `atlassian_dc` | **The only option.** Rovo is Cloud-only *and* remote: it runs in Atlassian's cloud and can never reach an instance behind your customer's VPN |

Pick per customer. What stays constant is the config shape, not the backend —
that part Atlassian does not offer.

## How the on-prem connection actually works

There is no MCP endpoint on the Atlassian side. Jira/Confluence DC do not speak
MCP at all: the MCP server **is** the local process your client spawns, and it
translates each tool call into ordinary REST calls against your instance.

```text
ON-PREM (DC)   client ──stdio (JSON-RPC)──► atlassian-mcp (local process)
                                               │ Authorization: Bearer <PAT>
                                               └─ socks5h://localhost:9999 ─► https://jira.internal/rest/api/2/…

CLOUD (Rovo)   client ──HTTPS streamable-HTTP + OAuth 2.1──► mcp.atlassian.com/v2/mcp ──► Atlassian internal APIs
```

The two differ at every layer — transport (stdio subprocess vs remote HTTP), auth
(PAT bearer vs OAuth 2.1), and who makes the REST call (your machine, inside the
tunnel, vs Atlassian's cloud). That last one is why Rovo can never serve DC.

| Purpose | Server / Data Center | Cloud |
| --- | --- | --- |
| Jira issues / JQL | `/rest/api/2/issue/{key}`, `/rest/api/2/search` | `/rest/api/3/…` (ADF bodies) |
| Jira agile | `/rest/agile/1.0/board/…` | same |
| Confluence content / CQL | `/rest/api/content`, `/rest/api/content/search` | `/wiki/api/v2/pages`, `/wiki/rest/api/…` |
| Auth header | `Authorization: Bearer <PAT>` | `Basic base64(email:token)` or OAuth |

Jira DC 9.12.x (LTS) and Confluence DC 9.2.x need nothing special: PATs have
existed since Jira 8.14 and the `/rest/api/2` surface is unchanged.

## Setup

```bash
mkdir -p ~/.config/atlassian-mcp
cp mcp/atlassian/profiles/onprem.env.example ~/.config/atlassian-mcp/onprem.env
chmod 600 ~/.config/atlassian-mcp/onprem.env   # it holds the token
$EDITOR ~/.config/atlassian-mcp/onprem.env
make install
```

The profile filename must match the server's `args` in the client configs
(`onprem`, `cloud`). For a second customer, add a server to all three — say
`atlassian_globex` with `args: ["globex"]` — and a `globex.env` beside it. Keep
the `atlassian_` prefix: the permission rules in `.claude/settings.json` match
on the server name.

Smoke test without a client:

```bash
ssh -D 9999 -q -N bastion &
atlassian-mcp onprem   # should start and print nothing; Ctrl-C to stop
```

## Version independence

The launcher never names an API version. `mcp-atlassian` detects Cloud vs
Server/DC from the URL and the fact that `*_PERSONAL_TOKEN` is set rather than
username + API token, then picks the right REST API per product (see the table
above) — so **the tool names and arguments are identical** on DC and on Cloud.
That is what makes one profile format cover both. Never set both auth styles in
one profile. Pin the server build per customer with `MCP_ATLASSIAN_VERSION=` if
you want reproducibility.

## Read-only, in four layers

Least trusted last — the model is the last line, not the first.

1. **The Atlassian account.** The PAT (DC) or API token (Cloud) belongs to a
   read-only user. On Cloud, use a *scoped* token with read scopes only. Nothing
   below matters if this is wrong.
2. **Tool filter** — `ENABLED_TOOLS` in `atlassian-mcp.sh` lists only read tools,
   so write tools are never advertised to the model at all.
3. **Server latch** — `READ_ONLY_MODE=true`, forced by the launcher regardless of
   what a profile says, so a mutating call is refused even if it is reachable.
4. **Client permissions** — `.claude/settings.json` denies every mutating tool
   name across all three servers (deny wins over allow in Claude Code) and allows
   the read ones without prompting. Gemini's equivalent is `excludeTools` in
   `.gemini/config/mcp_config.json`. Codex has no per-tool allowlist — there,
   layers 1–3 are the boundary.

Layer 4 is the only one that applies to `atlassian_rovo`, since you do not run
it. Tighten it further in Atlassian Administration, which lets an org admin
disable tools centrally.

`CONFLUENCE_SPACES_FILTER` / `JIRA_PROJECTS_FILTER` in the profile narrow *what*
is visible on top of that — worth setting per customer.

## VPN / SOCKS5

Set `ATLASSIAN_SOCKS_PROXY=socks5://localhost:9999` in the profile. The launcher
rewrites it to **`socks5h://`** so hostname resolution happens at the far end of
the tunnel — with plain `socks5://` the private Confluence hostname is resolved
locally and fails. It also pulls in `requests[socks]` so the SOCKS transport is
actually available, and sets `NO_PROXY` for loopback.

With `ATLASSIAN_MCP_RUNTIME=docker` the container runs with `--network host` so
`localhost:9999` still refers to your tunnel.

Caveats worth knowing:

- The tunnel must be up *before* the client starts the server; most clients spawn
  MCP servers once per session and do not retry.
- A corporate TLS-inspecting CA: add the CA to the system trust store rather than
  setting `CONFLUENCE_SSL_VERIFY=false`.
