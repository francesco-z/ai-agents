#!/usr/bin/env bash
# PreToolUse (Bash) hook: refuse `git push` whose target is main/master.
# Catches explicit refspecs (origin main, HEAD:master, feat:main) AND a bare
# `git push` / `git push origin` / `git push origin HEAD` while checked out on
# main/master — the cases plain permission rules can't see.
set -uo pipefail

input=$(cat)
# Claude and Codex send .tool_input.command and read hookSpecificOutput;
# Antigravity sends .toolCall.args.CommandLine and wants a decision on every
# exit (a bare {} is taken as deny): "ask" hands the call back to the normal
# permission rules, "deny" blocks it.
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .toolCall.args.CommandLine // ""')
agy=$(printf '%s' "$input" | jq -r 'if .toolCall then "1" else "" end')
# Antigravity runs hooks from the hooks.json directory, not the workspace.
[ -n "$agy" ] && cd "$(printf '%s' "$input" | jq -r '.workspacePaths[0] // "."')" 2>/dev/null
denied=""
trap '[ -n "$agy" ] && [ -z "$denied" ] && echo "{\"decision\":\"ask\"}"' EXIT

# Fast exit for anything that isn't a git push (also matches inside compound cmds)
printf '%s' "$cmd" | grep -Eq '(^|[;&|]|[[:space:]])git[[:space:]]+push([[:space:]]|$)' || exit 0

deny() {
  denied=1
  [ -n "$agy" ] && { jq -nc --arg r "$1" '{decision:"deny",reason:$r}'; exit 0; }
  jq -nc --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

current_branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""; }
is_protected() { case "$1" in main|master) return 0;; *) return 1;; esac; }

# Isolate the first `git push ...` invocation, stop at the next shell separator.
push_part=$(printf '%s' "$cmd" | sed -E 's/.*(^|[;&|[:space:]])git[[:space:]]+push/git push/')
push_part=$(printf '%s' "$push_part" | sed -E 's/[;&|].*$//')
args=$(printf '%s' "$push_part" | sed -E 's/^git[[:space:]]+push[[:space:]]*//')

# Split into remote (first non-flag token) and refspecs (the rest).
remote=""
refspecs=()
for tok in $args; do
  case "$tok" in -*) continue;; esac
  if [ -z "$remote" ]; then remote="$tok"; else refspecs+=("$tok"); fi
done

dest_of() { local r="$1"; [[ "$r" == *:* ]] && echo "${r##*:}" || echo "$r"; }

if [ "${#refspecs[@]}" -gt 0 ]; then
  for r in "${refspecs[@]}"; do
    d=$(dest_of "$r")
    if [ "$d" = "HEAD" ]; then
      b=$(current_branch)
      is_protected "$b" && deny "Refusing to push HEAD to $b. Push a feature branch and open a PR."
    elif is_protected "$d"; then
      deny "Refusing to push to '$d'. Push a feature branch and open a PR."
    fi
  done
  exit 0
fi

# No refspec: git push targets the current branch.
b=$(current_branch)
is_protected "$b" && deny "Refusing to push: current branch is '$b'. Push a feature branch and open a PR."
exit 0
