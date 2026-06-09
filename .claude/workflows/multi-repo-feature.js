export const meta = {
  name: 'multi-repo-feature',
  description: 'Write a feature across multiple repos in parallel: plan → implement (isolated worktrees) → UAT → DRAFT PR per repo. Never merges; never touches real environments.',
  phases: [
    { title: 'Plan', detail: 'architect splits each repo into parallel subtasks' },
    { title: 'Implement', detail: 'one implementer per subtask, isolated worktrees, parallel' },
    { title: 'UAT', detail: 'required acceptance testing per repo, local/ephemeral only' },
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
const PR = {
  type: 'object',
  properties: { url: { type: 'string' }, opened: { type: 'boolean' }, note: { type: 'string' } },
  required: ['opened', 'note'],
}

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

  // Stage 4: open a DRAFT PR only if UAT passed (human merges)
  (done) => {
    if (!done.uat || done.uat.verdict !== 'PASS') {
      log(`UAT did not pass for ${done.job.repo} — skipping PR`)
      return { repo: done.job.repo, uat: done.uat, pr: { opened: false, note: 'UAT not PASS; no PR opened' } }
    }
    return agent(
      `Repo: ${done.job.repo}\nOpen a DRAFT pull request for the feature branch(es) from this work:\n` +
      `${JSON.stringify(done.impls)}\nUAT result: ${JSON.stringify(done.uat)}\n\n` +
      `Push the feature branch, open with --draft, write a thorough body including the UAT manual checklist. ` +
      `Never merge, never enable auto-merge.`,
      { agentType: 'pr-author', phase: 'PR', label: `pr:${done.job.repo}`, schema: PR }
    ).then(pr => ({ repo: done.job.repo, uat: done.uat, pr }))
  }
)

const summary = results.filter(Boolean)
log(`Done. ${summary.filter(r => r.pr && r.pr.opened).length}/${summary.length} draft PRs opened. Review and merge manually.`)
return { repos: summary }
