# Kubernetes MCP server

Launcher and profiles for [containers/kubernetes-mcp-server](https://github.com/containers/kubernetes-mcp-server)
(Red Hat, Go, native client-go). It is **read-only by default**, and a profile
can switch it to writes. It was picked over
[Flux159/mcp-server-kubernetes](https://github.com/Flux159/mcp-server-kubernetes)
because it needs no `kubectl`/Node on the host and can deny Secrets on the
Kubernetes client. The full comparison is in
[k8s-readonly-mcp](https://github.com/francesco-z/k8s-readonly-mcp)
(`docs/comparison.md`).

| Server | Reaches | Transport | Credentials from |
| --- | --- | --- | --- |
| `kubernetes` | The contexts a profile selects | stdio launcher (`kubernetes-mcp`) | `~/.config/kubernetes-mcp/default.env` → kubeconfig files |

One profile, and one server, per customer or environment, so credentials,
proxy and mode never mix. Tools take a `context` argument.

## Modes

The launcher generates the server's TOML on every start from the profile
(`KUBERNETES_MCP_MODE`) and passes it as the only `--config`:

| Mode | TOML | Tools |
| --- | --- | --- |
| `read-only` (default) | `read_only = true` | 14 read tools (list/get/log/top/events), plus `helm_list` with the `helm` toolset |
| `non-destructive` | `disable_destructive = true` | adds `resources_create_or_update`, `pods_run` |
| `read-write` | — | adds deletes, `pods_exec`, `resources_scale` (and Helm install/uninstall with the `helm` toolset) |

In every mode, `configuration_view` (it prints the kubeconfig) is disabled, and
`v1/Secret` is in `denied_resources`. The server rejects Secret calls before
they reach the API server, unless `KUBERNETES_MCP_DENY_SECRETS=false`.

Client permissions add a layer. `.claude/settings.json` allows the read tools
and asks before each write tool, so switching the mode needs no settings edit.
Gemini has `trust: false`, so it confirms every call. Codex has no per-tool
rules, so there the mode is the boundary.

Upstream calls these settings best-effort guardrails, not a security boundary.
Toolsets that use their own HTTP clients (kiali, netobserv, observability) skip
`denied_resources`. GHSA-xq9m-mrj7-jv98 (a Kiali token leak) is fixed in 0.1.2,
the pinned version.

## Helm

The `helm` toolset has `helm_list` (read) and `helm_install`/`helm_uninstall`
(read-write mode only). There is no get values, history, upgrade or rollback.
Helm keeps releases in Secrets, so `helm_list` fails while Secrets are denied.
With `KUBERNETES_MCP_DENY_SECRETS=false` it works per namespace and returns
release metadata only (name, chart, version, status, revision). Across all
namespaces it can exceed the server's backend response limit. The price is
that `resources_get` can then read any Secret too.

## Kubeconfig and proxy

- **Kubeconfig**: read from the filesystem, never written.
  `KUBERNETES_MCP_KUBECONFIG` takes colon-separated files and globs (default
  `~/.kube/config`). `KUBERNETES_MCP_CONTEXTS` keeps only the contexts matching
  its globs. The launcher merges and flattens the result into
  `$XDG_RUNTIME_DIR/kubernetes-mcp/<profile>.kubeconfig` (tmpfs, `0600`,
  rewritten on every start), and that is the only file the server sees, mounted
  read-only in containers.
- **SOCKS5**: `KUBERNETES_MCP_SOCKS5_PROXY` becomes `proxy-url` on every cluster
  in the generated kubeconfig. Only API traffic is tunnelled; exec auth plugins
  (`aws eks get-token`, gcloud) keep the direct route. Hostnames resolve at the
  far end of the tunnel, so `socks5://` and `socks5h://` behave the same.
- **VPN**: containers run with `--network host`, so the host's VPN routes and
  DNS apply, as does a SOCKS tunnel on `localhost`.

## How it runs

| Runtime | Use when |
| --- | --- |
| `podman` (default), `docker` | Static credentials (tokens, client certs). Image `quay.io/containers/kubernetes_mcp_server`, run as your uid |
| `binary` | Contexts with exec auth plugins (`aws`, `gke-gcloud-auth-plugin`, `kubelogin`): they and `~/.aws` etc. don't exist in the image. Runs `kubernetes-mcp-server` from `PATH` |
| `npx` | Same as `binary`, via the npm package |

`KUBERNETES_MCP_VERSION` pins the server (default `0.1.2`). For `binary`,
install the matching release asset and check its digest:

```bash
gh release download v0.1.2 -R containers/kubernetes-mcp-server -p kubernetes-mcp-server-linux-amd64
gh api repos/containers/kubernetes-mcp-server/releases/tags/v0.1.2 \
  --jq '.assets[] | select(.name=="kubernetes-mcp-server-linux-amd64") | .digest'
sha256sum kubernetes-mcp-server-linux-amd64   # must match
install -m 755 kubernetes-mcp-server-linux-amd64 ~/.local/bin/kubernetes-mcp-server
```

Since v0.1.0 the server takes no runtime flags (`--read-only` and the rest are
gone); everything is TOML. That's why the launcher generates a file. The
launcher needs `kubectl` and `jq` on the host.

## Setup

```bash
mkdir -p ~/.config/kubernetes-mcp && chmod 700 ~/.config/kubernetes-mcp
cp mcp/kubernetes/profiles/default.env.example ~/.config/kubernetes-mcp/default.env
$EDITOR ~/.config/kubernetes-mcp/default.env   # kubeconfig, contexts, mode, proxy, runtime
make install
```

The checked-in configs only carry the generic `kubernetes` server (`args:
["default"]`). Customer profiles stay out of this public repo. Register each one
at user scope, with permissions in `~/.claude/settings.json`:

```bash
claude mcp add-json -s user kubernetes_acme '{"type":"stdio","command":"kubernetes-mcp","args":["acme"]}'
```

Then mirror the `mcp__kubernetes__*` rules from `.claude/settings.json` as
`mcp__kubernetes_acme__*`.

Smoke test without a client:

```bash
kubernetes-mcp acme   # waits on stdin for MCP messages; Ctrl-C to stop
cat ~/.cache/kubernetes-mcp/acme.toml                                       # server config
jq '.contexts[].name' "$XDG_RUNTIME_DIR/kubernetes-mcp/acme.kubeconfig"     # exposed contexts
```
