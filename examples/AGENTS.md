# AGENTS.md — cloudnative-pg-chart

Contract for any agent working in this repo. This repo is a **vendored mirror of the upstream
[CloudNativePG charts](https://github.com/cloudnative-pg/charts)** plus OpenShift
customizations. Companion values repo: `cloudnative-pg-procs-values`. Remote:
`bitbucket.example.com/scm/os/cloudnative-pg-chart.git`.

## Decisions in force
- **Operator:** Helm chart vendored here (not OLM).
- **Charts mirrored:** `cloudnative-pg/`, `cluster/`, `plugin-barman-cloud/`.
- **Migration:** manual `pg_dump`/restore; clusters bootstrap empty (`initdb`) — no `import`/`externalClusters`.
- **Backups:** Barman Cloud plugin → Cohesity S3 (S3-compatible).

## Branch model
| Branch | Rule |
|--------|------|
| `original` | Pristine upstream pull. **NEVER edit.** One commit per version. |
| `stage` | Non-prod customizations. Merge `original` in on each bump. |
| `main` | Production. Reached only by PR from `stage`, then tagged. |

Commits: `KUBE-<id> <action> <chart> <version>`. `stage`→`main` is always a PR.

## Initial build
1. On `original`: vendor the three charts at pinned versions into `cloudnative-pg/`, `cluster/`,
   `plugin-barman-cloud/` (`helm pull … --untar`). Commit untouched, recording versions.
2. Branch `stage`; apply + document customizations (rules below).
3. PR `stage`→`main`; tag `main` (e.g. `0.28.3`).

## Recurring upstream sync
`git checkout original` → re-vendor new version, commit → `git checkout stage && git merge original`
(preserve customizations) → PR `stage`→`main` → tag → bump `targetRevision` in the ArgoCD manifests.

## Customization rules (stage/main only, never original)
Keep minimal and documented in the commit body:
- Image registry → `nexus.example.com:8444` (mirror upstream images there).
- OpenShift defaults; org resource requests/limits.

## Images to mirror
`ghcr.io/cloudnative-pg/cloudnative-pg`, `ghcr.io/cloudnative-pg/postgresql`, `ghcr.io/cloudnative-pg/plugin-barman-cloud`

## ArgoCD
Templates in `examples/argocd/` (ApplicationSet + ACM Placement). Waves: operator 0, plugin 1,
cluster 2. The cluster app retries until operator CRDs exist. Copy into `clusteracm/app/gitops/`.

## Migration runbook (Bitnami HA → CNPG, manual pg_dump)
1. Pre-check: target major ≥ source; inventory DBs, roles, extensions, sizes.
2. Quiesce writes on the Bitnami release.
3. `pg_dumpall --globals-only -h <pgpool-svc> -U postgres > globals.sql`
4. `pg_dump -h <pgpool-svc> -U postgres -Fc -d <db> -f <db>.dump`  (per DB)
5. Provision the empty CNPG cluster (`cluster` chart, `bootstrap.initdb`).
6. `psql -h <cluster>-rw -U postgres -f globals.sql` ;
   `pg_restore -h <cluster>-rw -U postgres -d <db> --no-owner --role=<appuser> -j4 <db>.dump`
7. Reconcile extensions (must exist in the CNPG image); verify counts, sequences, `ANALYZE`.
8. Cutover: repoint app from Pgpool service to `<cluster>-rw`; decommission Bitnami.
9. Enable WAL archiving + `ScheduledBackup` (Barman Cloud plugin).
