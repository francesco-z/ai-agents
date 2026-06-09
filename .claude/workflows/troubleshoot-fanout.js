export const meta = {
  name: 'troubleshoot-fanout',
  description: 'Diagnose an incident/bug with competing hypotheses in parallel (IaC + app + upstream), cross-check adversarially, and synthesize one root cause with a PROPOSED fix. Read-only against real environments; nothing is applied or deployed.',
  phases: [
    { title: 'Hypothesize', detail: 'frame the symptom and generate competing theories' },
    { title: 'Investigate', detail: 'one investigator per hypothesis, in parallel' },
    { title: 'Cross-check', detail: 'adversarially confirm/refute each surviving theory' },
    { title: 'Synthesize', detail: 'single root cause + proposed (not applied) fix' },
  ],
}

// args: { symptom: "...", repo?: "...", context?: "...", hypotheses?: ["...", ...] }
const symptom = (args && args.symptom) || (typeof args === 'string' ? args : null)
if (!symptom) {
  log('No symptom provided. Pass { symptom: "...", repo?: "...", context?: "..." }')
  return { error: 'no-input' }
}
const ctx = (args && (args.context || args.repo)) ? `\nContext/repo: ${args.repo || ''} ${args.context || ''}` : ''

const HYPS = {
  type: 'object',
  properties: {
    hypotheses: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          theory: { type: 'string' },
          kind: { type: 'string', enum: ['iac', 'app', 'upstream'] },
          how_to_test: { type: 'string' },
        },
        required: ['id', 'theory', 'kind'],
      },
    },
  },
  required: ['hypotheses'],
}
const FINDING = {
  type: 'object',
  properties: {
    hypothesis_id: { type: 'string' },
    supported: { type: 'boolean' },
    confidence: { type: 'string', enum: ['low', 'medium', 'high'] },
    evidence: { type: 'string' },
  },
  required: ['hypothesis_id', 'supported', 'evidence'],
}
const VERDICT = {
  type: 'object',
  properties: {
    hypothesis_id: { type: 'string' },
    survives: { type: 'boolean' },
    reason: { type: 'string' },
  },
  required: ['hypothesis_id', 'survives', 'reason'],
}

const agentFor = (kind) => kind === 'iac' ? 'iac-troubleshooter' : kind === 'upstream' ? 'issue-researcher' : 'app-troubleshooter'

// Phase 1: frame + generate competing hypotheses (use provided ones if given)
phase('Hypothesize')
let hypotheses
if (args && Array.isArray(args.hypotheses) && args.hypotheses.length) {
  hypotheses = args.hypotheses.map((t, i) => ({ id: `h${i + 1}`, theory: t, kind: 'app' }))
} else {
  const h = await agent(
    `Symptom: ${symptom}${ctx}\n\nFrame the problem and generate 3–5 DISTINCT, independent competing hypotheses ` +
    `(config/IaC, application code, dependency/upstream, data). Classify each as iac | app | upstream and say how to test it read-only.`,
    { agentType: 'triage-coordinator', label: 'frame', schema: HYPS }
  )
  hypotheses = (h && h.hypotheses) || []
}
if (!hypotheses.length) { log('No hypotheses generated.'); return { error: 'no-hypotheses' } }
log(`Investigating ${hypotheses.length} competing hypotheses in parallel`)

// Phase 2: investigate each hypothesis in parallel (read-only diagnosis)
const findings = (await parallel(hypotheses.map(hyp => () => agent(
  `Symptom: ${symptom}${ctx}\n\nInvestigate ONLY this hypothesis (read-only diagnostics; never apply/deploy/delete):\n${JSON.stringify(hyp)}\n` +
  `Gather evidence and decide whether it is supported.`,
  { agentType: agentFor(hyp.kind), phase: 'Investigate', label: `inv:${hyp.id}:${hyp.kind}`, schema: FINDING }
))).filter(Boolean))

// Phase 3: adversarial cross-check of the supported theories
const supported = findings.filter(f => f.supported)
const checked = (await parallel(supported.map(f => () => agent(
  `Symptom: ${symptom}${ctx}\n\nAdversarially try to REFUTE this finding. Default to survives=false unless the evidence is strong ` +
  `and the alternatives are ruled out:\n${JSON.stringify(f)}\nAll findings: ${JSON.stringify(findings)}`,
  { agentType: 'triage-coordinator', phase: 'Cross-check', label: `check:${f.hypothesis_id}`, schema: VERDICT }
))).filter(Boolean))
const survivors = supported.filter(f => checked.find(v => v.hypothesis_id === f.hypothesis_id && v.survives))

// Phase 4: synthesize root cause + proposed (not applied) fix
phase('Synthesize')
const report = await agent(
  `Symptom: ${symptom}${ctx}\n\nFindings: ${JSON.stringify(findings)}\nCross-check verdicts: ${JSON.stringify(checked)}\n` +
  `Surviving hypotheses: ${JSON.stringify(survivors)}\n\n` +
  `Name the single most-likely ROOT CAUSE with evidence, and give a PROPOSED fix as a diff or step list. ` +
  `Do NOT apply anything. Mark any real-environment action as a manual step requiring human approval.`,
  { agentType: 'triage-coordinator', label: 'synthesize' }
)
return { symptom, hypotheses, findings, survivors, report }
