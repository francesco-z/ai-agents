# Kubernetes MCP server (read-only)

`k8s-readonly-mcp` is a small stdio MCP server that is read-only by design. It
works with any kubeconfig, including admin credentials, because the guard does
not depend on RBAC, a server flag or the model's behaviour.

| Tool | Like |
| --- | --- |
| `list_contexts` | `kubectl config get-contexts` (read from the local file, no API call) |
| `api_resources` | `kubectl api-resources` |
| `get` | `kubectl get` (table) / `kubectl get -o yaml` (without managedFields) |
| `logs` | `kubectl logs` (tail 200 by default, capped at 256 KiB) |

## The guard

All of the server's cluster traffic goes through one client, built in
`newCluster` (`k8s.go`). That client's transport is wrapped by `readOnly`
(`guard.go`), which inspects every outgoing HTTP request and rejects it before
it leaves the process unless:

- the method is `GET`, with no connection upgrade (no websocket/SPDY streams);
- the path is plain and canonical (no `..`, `//`, or escaped `/`) and lives under
  `/api`, `/apis` or `/version`;
- the resource is not `secrets` (named, listed or watched, in any namespace);
- the subresource is not `exec`, `attach`, `portforward` or `proxy`.

`guard_test.go` covers the rules and checks that denied requests never reach a
test API server. The MCP protocol layer (`main.go`) is hand-written JSON-RPC
with no SDK dependency, so the whole server is about 600 lines of Go.

## What it does not protect

- **Secrets outside Secret objects**: env literals in pod specs, ConfigMaps,
  CRDs that store credentials, and logs can still contain secrets.
- **Helm**: releases are stored as Secrets, so `helm list` and `helm get` can't
  be done through this server.
- **Your kubeconfig itself**: other tools (a shell, kubectl) still use the same
  credentials. Deny mutating `kubectl`/`helm` in client permissions too.

## Build and register

Run it natively, not in a container. Exec auth plugins (`aws`,
`gke-gcloud-auth-plugin`, `kubelogin`) and the kubeconfig must be on the host.

```bash
cd mcp/kubernetes
go test ./...
go build -o ~/.local/bin/k8s-readonly-mcp .
claude mcp add -s user kubernetes -- k8s-readonly-mcp
```

It uses `$KUBECONFIG` or `~/.kube/config`, like kubectl. To limit it to some
clusters, give it a dedicated file: `env KUBECONFIG=~/.kube/mcp-config k8s-readonly-mcp`.
