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
| `kubernetes` | Every context in one kubeconfig | stdio launcher (`kubernetes-mcp`) | `~/.config/kubernetes-mcp/default.env` → kubeconfig file |

## Modes

The launcher generates the server's TOML on every start from the profile
(`KUBERNETES_MCP_MODE`) and passes it as the only `--config`:

| Mode | TOML | Tools |
| --- | --- | --- |
| `read-only` (default) | `read_only = true` | 14 read tools (list/get/log/top/events) |
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
The known gaps are toolsets that use their own HTTP clients and skip
`denied_resources` (kiali, netobserv, observability), and `helm`, which reads
release Secrets internally. Keep `toolsets` at `core,config` unless you accept
that. GHSA-xq9m-mrj7-jv98 (a Kiali token leak) is fixed in 0.1.2, the pinned
version.

## Kubeconfig and proxy

- **Kubeconfig**: read from the filesystem, `KUBERNETES_MCP_KUBECONFIG`
  (default `~/.kube/config`). It is mounted read-only into the container. Every
  context in it is reachable, and tools take a `context` argument.
- **Container limits**: the kubeconfig must be self-contained. Paths to cert
  files and exec auth plugins (`aws`, `gke-gcloud-auth-plugin`, `kubelogin`)
  don't exist inside the image. Flatten it
  (`kubectl config view --flatten --minify --context X`) or use
  `KUBERNETES_MCP_RUNTIME=npx`, which runs on the host.
- **SOCKS5**: `KUBERNETES_MCP_SOCKS5_PROXY=socks5://localhost:9999` is passed
  to the server only (as `HTTPS_PROXY`). Hostnames resolve at the far end of
  the tunnel, so cluster names that only resolve inside the VPN work.
  Containers run with `--network host`, so a tunnel on `localhost` is
  reachable. For a proxy per cluster instead, client-go also honours
  `proxy-url: socks5://…` on a cluster entry in the kubeconfig.

## How it runs

- **Default runtime**: `podman`, `quay.io/containers/kubernetes_mcp_server`,
  pinned by `KUBERNETES_MCP_VERSION` (default `0.1.2`), run as your uid.
  `docker` works the same way. `npx` runs the npm package on the host.
- **Since v0.1.0** the server takes no runtime flags (`--read-only` and the
  rest are gone); everything is TOML. That's why the launcher generates a file.

## Setup

```bash
mkdir -p ~/.config/kubernetes-mcp
cp mcp/kubernetes/profiles/default.env.example ~/.config/kubernetes-mcp/default.env
$EDITOR ~/.config/kubernetes-mcp/default.env   # kubeconfig, mode, SOCKS proxy, runtime
make install
```

The profile name must match the server's `args` (`default`). For a second
setup, say a read-write profile for a lab, add a server to all three client
configs, `kubernetes_lab` with `args: ["lab"]`, a `lab.env` beside it, and
matching rules in `.claude/settings.json`.

Smoke test without a client:

```bash
kubernetes-mcp default   # waits on stdin for MCP messages; Ctrl-C to stop
cat ~/.cache/kubernetes-mcp/default.toml   # the generated server config
```
