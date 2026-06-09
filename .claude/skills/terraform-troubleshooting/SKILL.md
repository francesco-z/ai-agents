---
name: terraform-troubleshooting
description: Diagnose and fix Terraform errors — provider/auth failures, state drift and locks, plan/apply errors, module and version constraints. Use when working with .tf files or Terraform CLI output. Read-only diagnosis; applies require human approval.
when_to_use: terraform plan/apply errors, state lock, provider auth, drift, module version conflicts, .tf files in scope
allowed-tools: Bash(terraform validate*) Bash(terraform plan*) Bash(terraform state list*) Bash(terraform state show*) Bash(terraform providers*) Bash(terraform version*) Bash(terraform fmt*)
---

# Terraform troubleshooting

Diagnose with read-only commands. **Never** run `apply`, `destroy`, `import`, or `state rm/mv` — those are manual, human-approved steps (and are denied globally).

## Triage order
1. `terraform version` + provider versions (`terraform providers`) — confirm versions match `required_version`/`required_providers`.
2. `terraform validate` — syntax/type/reference errors before anything else.
3. `terraform plan` — read the *first* error; later errors are often cascades.
4. Inspect state read-only: `terraform state list`, `terraform state show <addr>`.

## Common failure signatures → cause
- **`Error: Inconsistent dependency lock file`** → `.terraform.lock.hcl` out of sync. Fix: `terraform init -upgrade` (local), commit the lock.
- **`Error acquiring the state lock`** → stale lock (crashed run / parallel run). Verify no run is active, then unlock is a *manual* approved step (`terraform force-unlock <id>`).
- **Provider auth (`No valid credential sources` / 403)** → missing/expired env creds or wrong assumed role/backend profile. Check `AWS_PROFILE`/`GOOGLE_APPLICATION_CREDENTIALS`/`ARM_*`, backend config, and `provider` blocks.
- **`Error: Reference to undeclared resource/variable`** → missing module output, var not declared, or wrong module path.
- **Drift (plan shows unexpected changes)** → out-of-band changes or provider default updates. Diff `state show` against config; propose `-refresh-only` or targeted alignment as a manual step.
- **Version constraint conflicts** → tighten/loosen `required_providers`; never silently widen a major version.

## Report format
Root cause → quoted evidence → proposed fix (diff or exact commands) → **manual apply step** the human must approve, with blast radius.
