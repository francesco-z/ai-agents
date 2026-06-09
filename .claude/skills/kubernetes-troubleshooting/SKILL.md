---
name: kubernetes-troubleshooting
description: Diagnose Kubernetes and Helm problems — pods Pending/CrashLoopBackOff/ImagePullBackOff, failed rollouts, OOMKills, RBAC and networking issues, Helm release failures. Use when working with k8s manifests, kubectl, or Helm output. Read-only diagnosis; mutations require human approval.
when_to_use: pods crashlooping/pending, failed deploys/rollouts, image pull errors, OOMKilled, RBAC denied, service/ingress not reachable, helm release failures
allowed-tools: Bash(kubectl get*) Bash(kubectl describe*) Bash(kubectl logs*) Bash(kubectl top*) Bash(kubectl auth can-i*) Bash(kubectl config view*) Bash(helm list*) Bash(helm status*) Bash(helm get*) Bash(helm template*)
---

# Kubernetes & Helm troubleshooting

Diagnose **read-only**. Never `apply/create/delete/edit/patch/drain/cordon` or `helm install/upgrade/uninstall/rollback` — those are manual, human-approved (and denied globally).

## First three commands
1. `kubectl get pods -n <ns> -o wide` — phase, restarts, node.
2. `kubectl describe pod <pod> -n <ns>` — Events at the bottom are usually the answer.
3. `kubectl logs <pod> -n <ns> [-p] [-c <container>]` — current and previous (`-p`) container logs.

## Signature → cause → check
- **Pending** → unschedulable: insufficient cpu/mem, no matching node (taints/affinity/nodeSelector), unbound PVC. Check `describe` Events + `kubectl get pvc`.
- **ImagePullBackOff / ErrImagePull** → wrong image/tag, private registry without `imagePullSecrets`, rate limit. Check image ref + secret.
- **CrashLoopBackOff** → app exits on start: read `logs -p`, check command/args, env/config, missing dependency or migration, failing readiness/liveness probe.
- **OOMKilled** (exit 137) → memory limit too low or leak. Check `describe` (Last State) + `kubectl top pod`.
- **RBAC `Forbidden`** → ServiceAccount lacks Role/RoleBinding. Confirm with `kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa>`.
- **Service unreachable** → selector mismatch (Service vs Pod labels), wrong port/targetPort, NetworkPolicy, no Endpoints (`kubectl get endpoints`).
- **Rollout stuck** → `kubectl rollout status`; failing new ReplicaSet probes; check `describe` of the new pods.
- **Helm release failed/pending** → `helm status`, `helm get manifest/values`; render locally with `helm template` to diff intended manifests.

## Report format
Root cause → quoted Events/logs → proposed manifest/values diff → **manual apply step** for human approval, with blast radius and rollback.
