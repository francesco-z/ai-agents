# Usage guide

Four ways to run this team, from lightest to heaviest. Pick by what the task needs.

| Mode | Who holds the plan | Inter-agent talk | Best for |
| --- | --- | --- | --- |
| **Subagents** | Claude, turn by turn | No (report back only) | Quick parallel research/implementation, isolated high-volume work |
| **Agent teams** | A lead session | Yes (shared task list + messaging) | Complex work needing discussion, you steering teammates directly |
| **Workflows** | A script (repeatable) | Via script variables | Many agents, fixed pipeline, resumable, cross-checked quality |
| **Nightly (`-p`)** | `orchestrator` agent | No | Hands-off automation; review draft PRs in the morning |

All four obey the same **manual gates**: draft PRs only, no real-environment
changes, local/ephemeral UAT (see `.claude/settings.json` deny rules).

---

## 1. Subagents (in-session, parallel)

Just ask. Claude delegates to the agents whose `description` matches, and runs
independent ones concurrently. Be explicit to force the split:

```text
Research, implement, and UAT the new /health endpoint. Use issue-researcher and
code-implementer in parallel, then uat-tester, then pr-author for a draft PR.
```

- `@agent-code-implementer` (or `@"code-implementer (agent)"`) forces a specific agent.
- "run in the background" / Ctrl+B makes a long agent async while you keep working.
- `code-implementer` runs in an isolated worktree, so several can implement at once.

## 2. Agent teams (you talk to teammates directly)

Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (set by the installer). Ask the
lead to build a team; teammates can reuse the agent definitions by name:

```text
Create an agent team to add OpenTelemetry tracing across ../svc-a and ../svc-b.
Spawn a code-implementer teammate per repo (each owns only its repo), a
uat-tester, and require plan approval before any teammate edits code. Only
approve plans that include tests. Open a draft PR per repo at the end — do not merge.
```

- Teammates load skills + MCP from your **settings**, not agent frontmatter, which is
  why `make install` puts skills and the GitHub MCP at user scope.
- `Shift+Down` cycles teammates (in-process); message any of them directly.
- For split panes, run inside `tmux`. Ask the lead to "clean up the team" when done.
- Give each teammate a different set of files to avoid conflicts.

## 3. Dynamic workflows (scripted, resumable, parallel at scale)

Saved in `.claude/workflows/` and available as slash commands after install.

**`/multi-repo-feature`** — plan → implement (parallel, isolated worktrees) →
UAT → draft PR, independently per repo. Pass args:

```text
Run /multi-repo-feature with { "task": "add a /readyz probe and wire it into the
Deployment", "repos": ["../svc-a", "../svc-b"] }
```
or per-repo tasks:
```text
Run /multi-repo-feature on [{"repo":"../svc-a","task":"..."},{"repo":"../svc-b","task":"..."}]
```

**`/troubleshoot-fanout`** — competing hypotheses investigated in parallel,
adversarially cross-checked, then one root cause + a *proposed* fix:

```text
Run /troubleshoot-fanout with { "symptom": "svc-a pods CrashLoopBackOff after the
1.36 cluster upgrade", "repo": "../svc-a" }
```

Watch progress with `/workflows`. Workflows run in the background; the session
stays free. They can't prompt mid-run, which is *why* PRs are left as drafts —
that's your sign-off point. To tweak a workflow, edit the `.js` file (re-run
`make install` to push it to `~/.claude/workflows/`) or edit the per-run script
path Claude reports.

> Tip: prefix any prompt with `ultracode` to have Claude author a one-off
> workflow for that task without saving it.

## 4. Programmatic / nightly

Write code overnight, review in the morning. The driver runs each queued task
through `claude -p --agent orchestrator`, opens draft PRs, and writes a report.

```bash
mkdir -p ~/.claude/nightly
cat > ~/.claude/nightly/queue.txt <<'EOF'
# one task per line; blank lines and #comments ignored
In ../svc-a, add structured request logging behind a LOG_JSON env flag, with tests.
In ../svc-b, migrate the config loader from JSON to YAML, keeping backward compat.
EOF

# run now (sequential; each task logged):
make nightly QUEUE=~/.claude/nightly/queue.txt WORK_ROOT=~/work
# report -> ~/.claude/nightly/report-<timestamp>.md  (lists draft PRs to review)
```

Schedule it with cron (token comes from `gh`, so keep `gh` logged in):

```cron
# 02:00 nightly, Mon–Fri
0 2 * * 1-5  cd ~/work && GITHUB_MCP_TOKEN="$(gh auth token)" \
  /path/to/ai-agents/scripts/nightly-code.sh ~/.claude/nightly/queue.txt ~/work >> ~/.claude/nightly/cron.log 2>&1
```

Prefer a managed routine? Use the `/schedule` skill inside Claude Code to create
a recurring remote agent instead of local cron.

In the morning: open each draft PR, run any real-environment UAT yourself, then
merge manually.

---

## How parallelism is maximized

- **Split first.** `code-architect` / `triage-coordinator` break work into the
  smallest independent units (by repo, then by concern) and mark dependencies.
- **Fan out.** Workflows use `parallel()`/`pipeline()`; teams use the shared task
  list; subagents run concurrently. Up to 16 agents run at once per workflow.
- **No collisions.** Implementers use isolated worktrees; same-file subtasks are
  sequenced, never run in parallel.
- **Converge.** Troubleshooting cross-checks hypotheses adversarially before
  committing to a root cause.

## Customizing

- Edit any agent in `.claude/agents/**`, skill in `.claude/skills/**`, or workflow
  in `.claude/workflows/**`, then `make install` to propagate to `~/.claude`.
- Adjust the safety gates in `.claude/settings.json` (`permissions.deny`). The
  installer merges these into `~/.claude/settings.json` so they apply everywhere.
- `make list` shows what's installed; `make uninstall` removes it.
