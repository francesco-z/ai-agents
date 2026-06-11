# aws-gitlab — project context for Claude Code agents

GitLab on AWS (EKS), deployed with the **upstream `gitlab/gitlab` Helm chart**
(repo `https://charts.gitlab.io`). Two environments: `gitlab-test` and `gitlab-live`.

## Layout
- `gitlab-<env>/helm-chart-resources/helm-values-<chart x-y-z>.yaml` — one values file **per chart version** (dashes, e.g. `helm-values-8-3-5.yaml`).
- `gitlab-<env>/terraform-resources/` — Terraform for the supporting AWS resources.
- `gitlab-<env>/aws-resources/` — CloudFormation (RDS, Redis, S3).
- `gitlab-<env>/utils/` — helper manifests (clients, cronjobs, secrets templates).

## Upgrade convention
An upgrade = bump the chart version, create a **new** `helm-values-<new>.yaml`
derived from the previous version's file (adjusted for chart changes), then:
```shell
cd gitlab-<env>
helm upgrade gitlab gitlab/gitlab --timeout 600s \
  -f helm-chart-resources/helm-values-<x-y-z>.yaml -n <namespace> --version <x.y.z>
```

## Current task
- **Current chart:** 8.3.5 (`gitlab-test/helm-chart-resources/helm-values-8-3-5.yaml`).
- **Target chart:** **9.11.6** (GitLab app **v18.11.5**).
- **Environment / namespace:** `gitlab-test`.
- ⚠️ **Major-version jump (8 → 9, app v17.3 → v18.11):** GitLab enforces a
  **required upgrade path** with mandatory stop-over versions for background
  migrations. Determine the exact intermediate chart versions to traverse and
  document them in the diff report and the UAT/upgrade checklist — a single direct
  `helm upgrade` is almost certainly NOT supported.

## Hard constraints for this task (OFFLINE)
- **Do NOT contact any cluster.** No `kubectl`/`helm` calls against a live release.
  Produce the diff from the chart artifacts and upstream changelogs only:
  `helm repo add/update`, `helm pull`, `helm show values/chart`, `helm template`,
  `helm lint` (all local), plus web/changelog research.
- **Never apply.** `helm upgrade`, `helm mapkubeapis` (without `--dry-run`),
  `kubectl apply/delete`, `terraform apply` are **manual, human-approved** steps
  (also denied globally). The agents prepare files and a checklist; the human runs them.
- **PRs are drafts only.** The human reviews and merges.

## Where new artifacts go
- New values file: `gitlab-test/helm-chart-resources/helm-values-9-11-6.yaml`
  (plus one per required intermediate stop-over, if the upgrade path needs them).
- Diff report + upgrade path + UAT plan: `gitlab-test/upgrade-9-11-6/` (create the folder).
