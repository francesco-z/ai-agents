---
name: multi-repo-workflow
description: How to plan and execute coding work that spans multiple repositories in parallel — discovering repos, splitting work so parallel agents don't collide, isolating each worker in its own git worktree, and coordinating cross-repo contracts. Use for any multi-repo feature or change.
when_to_use: a task touches more than one repository, planning parallel work across repos, avoiding file/branch conflicts between parallel implementers
---

# Multi-repo parallel workflow

## Repo layout
Repos are sibling directories under a working root, or attached with `--add-dir`. Discover them: each dir with a `.git` is one repo. Treat every repo as an independent unit of work and an independent PR.

## How to split for maximum parallelism
1. **By repository first** — different repos never conflict; one owner agent per repo.
2. **By concern within a repo** — module/layer/file group. Two subtasks that touch the **same file in the same repo must not run in parallel**: merge or sequence them.
3. **Make subtasks independent** — define cross-repo contracts (API shapes, schemas, message formats) up front so each worker codes against the contract, not against another worker's in-flight changes.
4. **Wave the dependencies** — wave 1 = zero-dependency subtasks (all parallel); later waves consume earlier outputs. Fewer dependencies = more parallelism.

## Isolation (avoid clobbering)
Each parallel `code-implementer` runs with `isolation: worktree`, so its edits land in a separate git worktree branched from the default branch. This lets many implementers work at once without overwriting each other. One repo + multiple subtasks → each gets its own branch; merge order is the human's decision via PRs.

## Per-repo pipeline
For each repo: research (optional, parallel) → implement (parallel across repos) → **UAT (required)** → **draft PR (required, never merged)**. Report status per repo separately so partial progress is clear.

## Manual gates (always)
- One **draft** PR per repo; the human reviews and merges.
- No real-environment tests or infra changes — list them as manual steps in the PR.
