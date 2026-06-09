# ai-agents

A reusable team of custom Claude Code subagents, DevOps skills, and dynamic
workflows for **parallel multi-repo code writing** and **cross-stack
troubleshooting** (Terraform, Kubernetes/Helm, Node/npm, Go, Python).

The canonical source lives in this repo (version-controlled). `make install`
copies it into your user-level config (`~/.claude`) so it works in **all** your
repositories.

## What's inside

| Type | Name | Purpose |
| --- | --- | --- |
| Agent | `orchestrator` | Main-thread coordinator (used for `--agent`/nightly): splits work, delegates in parallel, enforces gates |
| Agent | `code-architect` | Splits a feature into independent, parallel subtasks across repos |
| Agent | `code-implementer` | Implements one subtask in an **isolated git worktree** (parallel-safe) |
| Agent | `uat-tester` | **Required** UAT gate — local/ephemeral only, PASS/FAIL verdict |
| Agent | `pr-author` | Opens **draft** PRs, never merges |
| Agent | `triage-coordinator` | Leads troubleshooting via competing hypotheses |
| Agent | `iac-troubleshooter` | Terraform/Kubernetes/Helm diagnosis (read-only) |
| Agent | `app-troubleshooter` | Node/npm, Go, Python build & runtime errors |
| Agent | `issue-researcher` | Finds known issues/fixes on GitHub + the web |
| Skill | `terraform-/kubernetes-troubleshooting` | IaC diagnostic playbooks |
| Skill | `node-npm-/go-/python-` | App-language playbooks |
| Skill | `uat-testing`, `multi-repo-workflow` | Procedures for the gates & parallel splitting |
| Workflow | `/multi-repo-feature` | plan → implement (parallel) → UAT → draft PR, per repo |
| Workflow | `/troubleshoot-fanout` | parallel hypotheses → adversarial cross-check → root cause + proposed fix |
| MCP | `github` | Official remote GitHub MCP (issues, PRs, code search) |

## Setup

Requires Claude Code ≥ 2.1.154, `jq`, `gh` (authenticated), and the `claude` CLI.

```bash
make install
```

Then finish two steps:

1. **GitHub MCP token** — read at runtime, never stored. Add to `~/.bashrc`/`~/.zshrc`:
   ```bash
   export GITHUB_MCP_TOKEN="$(gh auth token)"
   ```
2. **Agent teams** (experimental, opt-in) are enabled globally by the installer via
   `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in `~/.claude/settings.json`. To use an
   env var instead, add to your shell profile:
   ```bash
   export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
   ```

Restart Claude Code, then verify: `/agents`, `/skills`, and type `/` to see the workflows.

## Quick start

```text
# Parallel feature across repos (draft PRs at the end):
/multi-repo-feature   (then describe the task + repos, or pass args)

# Parallel root-cause troubleshooting:
/troubleshoot-fanout  (then describe the symptom)

# An agent team you talk to directly (needs teams enabled):
Create an agent team to add feature X across ../svc-a and ../svc-b. Use code-implementer
teammates, require plan approval, and a uat-tester before any draft PR.

# Nightly, hands-off:
make nightly QUEUE=~/.claude/nightly/queue.txt WORK_ROOT=~/work
```

See **[docs/USAGE.md](docs/USAGE.md)** for detailed usage, the four execution
modes (subagents / agent teams / workflows / nightly), and the safety model.

## Safety model — manual gates (never bypassed)

- **PRs are drafts only.** No agent ever merges; `gh pr merge` is denied. You merge.
- **No real-environment changes.** `terraform apply/destroy`, `kubectl apply/delete`,
  `helm install/upgrade`, etc. are denied in `settings.json` — the block applies even
  inside workflows and nightly runs.
- **UAT is local/ephemeral.** Real/staging/prod tests are emitted as a manual checklist
  for your approval, never executed by an agent.

## Working across multiple repos

Run Claude Code from a parent directory that contains your repo clones as
siblings, or attach them with `--add-dir`. Each `code-implementer` works in its
own worktree, so parallel workers never clobber each other. One repo → one PR.
