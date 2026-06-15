# AGENTS.md — cloudnative-pg-chart

Contract for any agent working in this repo. This repo is a **vendored mirror of the upstream
[CloudNativePG charts](https://github.com/cloudnative-pg/charts)** plus Valbruna OpenShift
customizations. Companion values repo: `cloudnative-pg-procs-values`. Remote:
`bitbucket.valbruna.it/scm/os/cloudnative-pg-chart.git`.

## Decisions in force
- **Operator install:** Helm chart vendored here (ArgoCD owns it). Do **not** assume OLM.
- **Charts mirrored:** `cluster/`, `cloudnative-pg/` (operator), `plugin-barman-cloud/`.
- **Migration from Bitnami:** manual `pg_dump`/`pg_restore`; clusters bootstrap empty (`initdb`).
  Do **not** add `bootstrap.initdb.import` / `externalClusters`.

## Branch model (mirror of postgresql-ha-chart)
| Branch     | Rule |
|------------|------|
| `original` | Pristine upstream pull. **NEVER edit.** One commit per upstream version. |
| `stage`    | Branched from `original`. Non-prod customizations live here. Merge `original` in on each bump. |
| `main`     | Production. Only reached by PR from `stage`. |

- Commit messages: `KUBE-<id> <action> <chart> <version>` (e.g. `KUBE-NN initial pull cluster 0.x.y`).
- `stage` → `main` is always a **pull request**, never a direct push.

## Initial build (one-time)
1. On `original`: vendor the three upstream charts at pinned versions into subdirs
   `cloudnative-pg/`, `cluster/`, `plugin-barman-cloud/` (e.g. `helm pull` + extract, or git subtree).
   Commit untouched. Record exact upstream versions in commit message.
2. Create `stage` from `original`. Apply + document customizations (see rules below).
3. Open PR `stage` → `main`.
4. Keep `README.md`, this `AGENTS.md`, and `CLAUDE.md` on all branches.

## Recurring upstream sync
1. `git checkout original`
2. Re-vendor the new upstream version(s); commit `KUBE-<id> chart <name> <version>`.
3. `git checkout stage && git merge original`; resolve conflicts preserving customizations.
4. PR `stage` → `main`.

## Customization rules
Allowed on `stage`/`main` only (never `original`). Keep them minimal and documented:
- Default image registry → `itviacvls0332.valbruna.it:8444` (mirror upstream images there).
- OpenShift defaults (SCC-friendly; CNPG already supports `restricted-v2`).
- Resource requests/limits and other org defaults.
Document every customization in the commit body so the next sync can re-apply it.

## Images to mirror (internal registry)
- `ghcr.io/cloudnative-pg/cloudnative-pg`
- `ghcr.io/cloudnative-pg/postgresql`
- `ghcr.io/cloudnative-pg/plugin-barman-cloud`

## Migration runbook (Bitnami postgresql-ha → CNPG, manual pg_dump)
Cluster bootstraps empty (`initdb`); migrate data in a maintenance window:
1. Pre-check: target major ≥ source; inventory DBs, roles, extensions, sizes.
2. Quiesce writes on the Bitnami release.
3. `pg_dumpall --globals-only -h <pgpool-svc> -U postgres > globals.sql`
4. `pg_dump -h <pgpool-svc> -U postgres -Fc -d <db> -f <db>.dump`  (per DB)
5. Provision the empty CNPG cluster (`cluster` chart, `bootstrap.initdb`).
6. `psql -h <cluster>-rw -U postgres -f globals.sql`
   `pg_restore -h <cluster>-rw -U postgres -d <db> --no-owner --role=<appuser> -j4 <db>.dump`
7. Reconcile extensions (must exist in the CNPG image); verify row counts, sequences, `ANALYZE`.
8. Cutover: repoint app from the Pgpool service to `<cluster>-rw`; decommission Bitnami.
9. Enable WAL archiving + `ScheduledBackup` (Barman Cloud plugin).
