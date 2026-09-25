# Grafana MCP server, remote on Kubernetes

One shared, read-only `mcp-grafana` behind an Ingress, instead of one container
per laptop. Clients reach it over streamable HTTP at `https://<host>/mcp`.

```text
client ──HTTPS + Bearer <server token>──► Ingress ──► grafana-mcp pod ──service account token──► Grafana
```

Uses the [`grafana-community/grafana-mcp`](https://github.com/grafana-community/helm-charts)
chart — `grafana/grafana-mcp` is deprecated and stuck on an old server build.

## What `values.yaml` sets

| Concern | How |
| --- | --- |
| Transport | `-t streamable-http` (the image default is SSE) |
| Read-only | `--disable-write` in `extraArgs`, plus a Viewer service account |
| Caller auth | `MCP_GRAFANA_SERVER_TOKEN` from a Secret; requests without it get `401` |
| DNS rebinding | `--allowed-hosts` = ingress host + in-cluster Service names |
| Probes | `tcpSocket` — an `httpGet` probe would fail the Host allowlist |
| Streaming | nginx buffering off, 1h read/send timeouts |

Replace `acme.example` hostnames, `grafana.url` and `GRAFANA_ORG_ID` before
installing. If you change the release name or namespace, update the Service names
in `--allowed-hosts` to match.

## Install

```bash
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo update

kubectl create namespace grafana-mcp
kubectl -n grafana-mcp create secret generic grafana-mcp-grafana-token \
  --from-literal=token='glsa_XXXX'                 # Grafana service account, Viewer
kubectl -n grafana-mcp create secret generic grafana-mcp-server-token \
  --from-literal=token="$(openssl rand -hex 32)"   # what MCP clients present

helm upgrade --install grafana-mcp grafana-community/grafana-mcp \
  -n grafana-mcp -f mcp/grafana/helm/values.yaml
```

`grafana-mcp-tls` must exist too, or add a `cert-manager.io/cluster-issuer`
annotation to the Ingress. Check: `curl -s https://grafana-mcp.acme.example/healthz`.

## Connect clients

Register it as `grafana_remote` — the permission rules in `.claude/settings.json`
already cover that name. The token is read from the environment, never stored:

```bash
export GRAFANA_MCP_SERVER_TOKEN="$(kubectl -n grafana-mcp get secret grafana-mcp-server-token -o jsonpath='{.data.token}' | base64 -d)"
```

Claude Code (native HTTP; `${VAR}` is expanded at spawn):

```bash
claude mcp add-json -s user grafana_remote '{
  "type": "http",
  "url": "https://grafana-mcp.acme.example/mcp",
  "headers": { "Authorization": "Bearer ${GRAFANA_MCP_SERVER_TOKEN}" }
}'
```

Gemini / Antigravity and Codex, through the `mcp-remote` bridge:

```json
"grafana_remote": {
  "command": "sh",
  "args": ["-c", "exec npx -y mcp-remote https://grafana-mcp.acme.example/mcp --header \"Authorization: Bearer $GRAFANA_MCP_SERVER_TOKEN\""]
}
```

Callers can pick another org per request with an `X-Grafana-Org-Id` header.
