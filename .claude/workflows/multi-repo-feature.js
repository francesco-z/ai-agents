export const meta = {
  name: 'multi-repo-feature',
  description: 'Write a feature across multiple repos in parallel: plan → implement (isolated worktrees) → UAT → DRAFT PR per repo. Never merges; never touches real environments.',
  phases: [
    { title: 'Plan', detail: 'architect splits each repo into parallel subtasks' },
    { title: 'Implement', detail: 'one implementer per subtask, isolated worktrees, parallel' },
    { title: 'UAT', detail: 'required acceptance testing per repo, local/ephemeral only' },
    { title: 'Review', detail: 'adversarial code review; debate fixes back to implementer until APPROVE' },
    { title: 'PR', detail: 'open a draft PR per repo (human merges)' },
  ],
}

// ---- Input -------------------------------------------------------------
// args accepts:
//   { task: "...", repos: ["pathA", "pathB"] }   -> same task across repos
//   [ { repo: "pathA", task: "..." }, ... ]       -> per-repo tasks
//   { repo: "pathA", task: "..." }                -> single repo
function normalizeJobs(a) {
  if (Array.isArray(a)) return a
  if (a && Array.isArray(a.repos)) return a.repos.map(r => ({ repo: r, task: a.task }))
  if (a && (a.repo || a.task)) return [{ repo: a.repo || '.', task: a.task }]
  return []
}
const jobs = normalizeJobs(args)
if (jobs.length === 0) {
  log('No repos/task provided. Pass e.g. { task: "...", repos: ["../svc-a", "../svc-b"] }')
  return { error: 'no-input' }
}
log(`Planning ${jobs.length} repo(s) in parallel`)

const PLAN = {
  type: 'object',
  properties: {
    repo: { type: 'string' },
    subtasks: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          title: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          depends_on: { type: 'array', items: { type: 'string' } },
          acceptance: { type: 'string' },
          risk: { type: 'string' },
        },
        required: ['id', 'title', 'acceptance'],
      },
    },
    acceptance_criteria: { type: 'array', items: { type: 'string' } },
  },
  required: ['repo', 'subtasks', 'acceptance_criteria'],
}
const IMPL = {
  type: 'object',
  properties: {
    subtask_id: { type: 'string' },
    branch: { type: 'string' },
    files_changed: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    follow_ups: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary'],
}
const UAT = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['PASS', 'FAIL'] },
    details: { type: 'string' },
    manual_checklist: { type: 'array', items: { type: 'string' } },
  },
  required: ['verdict', 'details'],
}
const REVIEW = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['APPROVE', 'CHANGES_REQUESTED'] },
    summary: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          location: { type: 'string' },
          problem: { type: 'string' },
          suggested_fix: { type: 'string' },
        },
        required: ['severity', 'problem'],
      },
    },
  },
  required: ['verdict', 'summary'],
}
const PR = {
  type: 'object',
  properties: { url: { type: 'string' }, opened: { type: 'boolean' }, note: { type: 'string' } },
  required: ['opened', 'note'],
}

// Max review<->implementer debate rounds before we stop and defer to a human.
const MAX_REVIEW_ROUNDS = 3
const isBlocking = f => f.severity === 'blocker' || f.severity === 'major'

// ---- Pipeline: each repo flows independently through all four stages ----
const results = await pipeline(
  jobs,

  // Stage 1: plan + split into parallel subtasks
  (job) => agent(
    `Repo: ${job.repo}\nTask: ${job.task}\n\nProduce a subtask plan optimized for parallel execution. ` +
    `Split by concern; no two subtasks may touch the same file. List acceptance criteria.`,
    { agentType: 'code-architect', phase: 'Plan', label: `plan:${job.repo}`, schema: PLAN }
  ),

  // Stage 2: implement every subtask in parallel, each in its own worktree
  (plan, job) => parallel(
    (plan.subtasks || []).map(st => () => agent(
      `Repo: ${job.repo}\nImplement ONLY this subtask:\n${JSON.stringify(st)}\n\n` +
      `Stay within the listed files. Add unit tests. Commit to a feature branch in your worktree. Do not open a PR.`,
      { agentType: 'code-implementer', phase: 'Implement', label: `impl:${job.repo}:${st.id}`, isolation: 'worktree', schema: IMPL }
    ))
  ).then(impls => ({ job, plan, impls: impls.filter(Boolean) })),

  // Stage 3: required UAT in a local/ephemeral environment
  (built) => agent(
    `Repo: ${built.job.repo}\nAcceptance criteria: ${JSON.stringify(built.plan.acceptance_criteria)}\n` +
    `Implemented work: ${JSON.stringify(built.impls)}\n\n` +
    `Build and run lint/unit/integration/UAT against LOCAL or EPHEMERAL targets only. ` +
    `Return PASS only if all criteria are met. List any steps that need a real environment as a manual checklist — do not run them.`,
    { agentType: 'uat-tester', phase: 'UAT', label: `uat:${built.job.repo}`, schema: UAT }
  ).then(uat => ({ ...built, uat })),

  // Stage 4: adversarial code review AFTER UAT, BEFORE the PR.
  // Debate loop: reviewer finds problems -> implementer fixes -> re-review, until APPROVE or cap.
  async (checked) => {
    if (!checked.uat || checked.uat.verdict !== 'PASS') {
      return { ...checked, review: null } // UAT already failed; PR stage will skip.
    }
    let review = null
    for (let round = 1; round <= MAX_REVIEW_ROUNDS; round++) {
      review = await agent(
        `Repo: ${checked.job.repo}\nAcceptance criteria: ${JSON.stringify(checked.plan.acceptance_criteria)}\n` +
        `Implemented work (branches/files): ${JSON.stringify(checked.impls)}\n\n` +
        `Round ${round}/${MAX_REVIEW_ROUNDS}. Adversarially review the diff on the feature branch(es). ` +
        `Hunt for correctness, security, regression, and design defects. ` +
        `Return APPROVE only if there are no blocking (blocker/major) findings.`,
        { agentType: 'code-reviewer', phase: 'Review', label: `review:${checked.job.repo}:r${round}`, schema: REVIEW }
      )
      const blockers = (review?.findings || []).filter(isBlocking)
      if (!review || review.verdict === 'APPROVE' || blockers.length === 0) break

      if (round === MAX_REVIEW_ROUNDS) {
        log(`Review still blocking for ${checked.job.repo} after ${round} rounds — deferring to human`)
        break
      }
      log(`Review round ${round} for ${checked.job.repo}: ${blockers.length} blocking finding(s) — sending back to implementer`)
      // Route blocking findings back to an implementer to fix on the same branch(es).
      await parallel(
        checked.impls.map(impl => () => agent(
          `Repo: ${checked.job.repo}\nBranch: ${impl.branch || '(feature branch)'}\n` +
          `Code review requested changes. Fix ONLY these blocking findings on the existing branch, ` +
          `keep the fix minimal and in-style, add/adjust tests, and commit:\n${JSON.stringify(blockers)}`,
          { agentType: 'code-implementer', phase: 'Implement', label: `fix:${checked.job.repo}:r${round}`, isolation: 'worktree', schema: IMPL }
        ))
      )
    }
    return { ...checked, review }
  },

  // Stage 5: open a DRAFT PR only if UAT passed AND review approved (human merges)
  (done) => {
    if (!done.uat || done.uat.verdict !== 'PASS') {
      log(`UAT did not pass for ${done.job.repo} — skipping PR`)
      return { repo: done.job.repo, uat: done.uat, review: done.review, pr: { opened: false, note: 'UAT not PASS; no PR opened' } }
    }
    if (!done.review || done.review.verdict !== 'APPROVE') {
      log(`Code review did not APPROVE for ${done.job.repo} — skipping PR`)
      return { repo: done.job.repo, uat: done.uat, review: done.review, pr: { opened: false, note: 'Code review not APPROVE; no PR opened' } }
    }
    return agent(
      `Repo: ${done.job.repo}\nOpen a DRAFT pull request for the feature branch(es) from this work:\n` +
      `${JSON.stringify(done.impls)}\nUAT result: ${JSON.stringify(done.uat)}\n` +
      `Code review: ${JSON.stringify(done.review)}\n\n` +
      `Push the feature branch, open with --draft, write a thorough body including the UAT manual checklist ` +
      `and a note that code review APPROVED. Never merge, never enable auto-merge.`,
      { agentType: 'pr-author', phase: 'PR', label: `pr:${done.job.repo}`, schema: PR }
    ).then(pr => ({ repo: done.job.repo, uat: done.uat, review: done.review, pr }))
  }
)

const summary = results.filter(Boolean)
log(`Done. ${summary.filter(r => r.pr && r.pr.opened).length}/${summary.length} draft PRs opened. Review and merge manually.`)
return { repos: summary }
