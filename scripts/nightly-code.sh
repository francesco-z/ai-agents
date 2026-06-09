#!/usr/bin/env bash
# Programmatic / nightly driver: run queued coding tasks headlessly, open DRAFT
# PRs, and leave a morning report. Never merges, never touches real environments
# (enforced by the deny rules in settings.json + the orchestrator agent prompt).
#
# Usage:
#   scripts/nightly-code.sh [queue-file] [work-root]
#
# queue-file : text file, ONE task per line (blank lines / # comments ignored).
#              Default: $HOME/.claude/nightly/queue.txt
# work-root  : directory that contains the sibling repos to work across.
#              Default: current directory.
#
# Each task line is handed to `claude -p --agent orchestrator`, which decomposes
# it, delegates to specialists in parallel, runs UAT, and opens a draft PR.
set -uo pipefail

QUEUE="${1:-$HOME/.claude/nightly/queue.txt}"
WORK_ROOT="${2:-$PWD}"
BASE="$HOME/.claude/nightly"
LOGDIR="$BASE/logs"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$BASE/report-$STAMP.md"
mkdir -p "$LOGDIR"

# GitHub MCP + gh both need a token; source it at runtime, never store it.
export GITHUB_MCP_TOKEN="${GITHUB_MCP_TOKEN:-$(gh auth token 2>/dev/null || true)}"

if [ ! -f "$QUEUE" ]; then
  echo "No queue file at $QUEUE. Create it with one task per line." >&2
  exit 1
fi

GUARD='SAFETY: Never merge PRs (open drafts only). Never run real-environment
infrastructure changes (no terraform apply/destroy, no kubectl apply/delete, no
deploys). UAT runs locally/ephemerally only. Stop and record any step that needs
human approval. Work across the repos found under the current directory.'

{
  echo "# Nightly run $STAMP"
  echo
  echo "- Work root: \`$WORK_ROOT\`"
  echo "- Queue: \`$QUEUE\`"
  echo
  echo "## Tasks"
} > "$REPORT"

n=0
while IFS= read -r task || [ -n "$task" ]; do
  case "$task" in ''|\#*) continue;; esac
  n=$((n+1))
  log="$LOGDIR/task-$STAMP-$n.log"
  echo "==> [$n] $task"
  echo "    log: $log"

  ( cd "$WORK_ROOT" && \
    claude -p "$task" \
      --agent orchestrator \
      --permission-mode acceptEdits \
      --append-system-prompt "$GUARD" \
  ) >"$log" 2>&1
  rc=$?

  {
    echo
    echo "### [$n] $task"
    echo "- exit: $rc"
    echo "- log: \`$log\`"
  } >> "$REPORT"
done < "$QUEUE"

# Collect the draft PRs that exist now, for your morning review.
{
  echo
  echo "## Draft PRs awaiting your review/merge"
  echo
  if command -v gh >/dev/null 2>&1; then
    for d in "$WORK_ROOT"/*/; do
      [ -d "$d/.git" ] || continue
      prs="$(cd "$d" && gh pr list --draft --json url,title,headRefName \
            --jq '.[] | "- [\(.title)](\(.url)) — `\(.headRefName)`"' 2>/dev/null)"
      [ -n "$prs" ] && { echo "**$(basename "$d")**"; echo "$prs"; echo; }
    done
  fi
  echo "_Review each draft, run any real-environment UAT yourself, then merge manually._"
} >> "$REPORT"

echo "==> Ran $n task(s). Report: $REPORT"
