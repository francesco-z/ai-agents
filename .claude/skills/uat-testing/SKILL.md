---
name: uat-testing
description: Procedure for user-acceptance testing a change in a LOCAL or EPHEMERAL environment before a PR. Build, run the test pyramid, exercise acceptance criteria against localhost/ephemeral targets, and produce a PASS/FAIL verdict plus a manual checklist for any real-environment steps. Never tests against real/staging/production.
when_to_use: before opening a PR, verifying a feature meets acceptance criteria, validating a fix end to end locally
---

# UAT in a local / ephemeral environment

Goal: decide PASS/FAIL against acceptance criteria using only safe targets. Real-environment validation is a **manual, human-approved** step you never perform.

## Safe targets only
localhost, ephemeral containers (`docker run --rm`), kind/minikube, throwaway test databases, mocks/stubs. **Never** real, shared, staging, or production systems; never deploy; never `kubectl apply/delete` against a live cluster.

## Procedure
1. **Identify acceptance criteria** — the observable behaviors that define "done".
2. **Build** the project from a clean state (note exact commands).
3. **Run the pyramid, fast→slow**: lint/typecheck → unit → integration (against ephemeral deps) → end-to-end/UAT (drive the app locally and observe real behavior, not just exit codes).
4. **Exercise each acceptance criterion explicitly** and record the result.
5. **Verdict**: PASS only if every criterion is met and all tests pass.

## Output
- **Verdict: PASS / FAIL**
- Commands run + key output (failures quoted in full)
- Acceptance criteria → met / not-met / needs-human-verification
- Defects with reproduction steps (for FAIL)
- **Manual UAT checklist** for anything that genuinely needs a real/staging environment — written for the human to run under their approval, never executed here.

Do not edit code to make tests pass — report failures so an implementer fixes them.
