export const meta = {
  name: 'appkit-phase3-audit',
  description: 'Adversarial audit of appkit-private-apis + appkit-app-inspector: ObjC-runtime symbols, PHK commands, flexscope frozen-contract flags, advisory accuracy',
  phases: [
    { title: 'Audit', detail: 'per-file: verify symbols / commands / flags / advisory framing' },
    { title: 'Consistency', detail: 'reciprocal advisory, dev-box distinction, frontmatter' },
  ],
}

const SK = '/Users/orion/Developer/Templates/skills/mac-dev-skills/plugins/appkit/skills'
const FX = '/Users/orion/Developer/Projects/flexscope'
const PRIV = `${SK}/appkit-private-apis`
const INSP = `${SK}/appkit-app-inspector`

const PRIV_FILES = ['SKILL.md','references/private-header-kit.md','references/declaring-and-calling.md','references/swizzling.md','references/distribution-advisory.md']
const INSP_FILES = ['SKILL.md','references/cli-contract.md','references/filter-drill-and-selectors.md','references/doctor-and-dev-box.md','references/failure-signatures.md']

const AUDIT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['file','checked','issues','verdict'],
  properties: {
    file: { type: 'string' },
    checked: { type: 'number', description: 'how many symbols/commands/flags you verified against ground truth' },
    issues: { type: 'array', items: { type: 'object', additionalProperties: false,
      required: ['kind','evidence','fix'],
      properties: {
        kind: { type: 'string', enum: ['symbol-not-found','wrong-phk-command','wrong-flexscope-flag','invented-unspecified-default','inaccurate-advisory','wrong-exit-code','factual-error','broken-markdown','other'] },
        evidence: { type: 'string' }, fix: { type: 'string' } } } },
    verdict: { type: 'string', description: '"clean" or a 1-2 sentence summary of must-fix issues.' },
  },
}

function privPrompt(file) {
  return `Hostile auditor. Assume the author hallucinated. FILE: ${PRIV}/${file}

Read it, then verify:
1. **ObjC-runtime / C symbols**: every runtime symbol it names (method_exchangeImplementations, class_getInstanceMethod, method_setImplementation, method_getImplementation, class_addMethod, class_replaceMethod, imp_implementationWithBlock, object_getIvar, class_getInstanceVariable, dlopen, dlsym, NSClassFromString, NSSelectorFromString, etc.) MUST exist. Verify: \`SDK=$(xcrun --sdk macosx --show-sdk-path); grep -rn '<symbol>' "$SDK/usr/include/objc/" "$SDK/usr/include/dlfcn.h"\` (Foundation symbols: grep the Foundation framework headers). Flag any \`symbol-not-found\`.
2. **PrivateHeaderKit commands**: the DUMP command must be \`privateheaderkit-dump\` (NOT \`headerdump\`); macOS dumps MUST pass \`--platform macos\` (default is ios); install is \`swift run -c release privateheaderkit-install\`. Flag \`wrong-phk-command\` for any deviation. Also flag if the file claims PHK needs SIP/AMFI off (it does NOT — static dumper).
3. **Advisory accuracy** (critical): if the file discusses shipping/App Store, it MUST frame review as case-by-case (may reject, not auto-reject) AND name Developer ID + notarization as the escape hatch, AND must NOT frame static-scanner-evasion as making it "safe to ship". Flag \`inaccurate-advisory\` for a one-sided "will be rejected", a missing escape hatch where shipping is discussed, or evasion-as-safety.
4. Broken markdown (unbalanced code fences), obvious factual errors.
Cite evidence + the fix. Only real problems. Return structured audit.`
}

function inspPrompt(file) {
  return `Hostile auditor. FILE: ${INSP}/${file}. This drives the flexscope CLI; its specs are the frozen contract at ${FX}.

Read the file, then verify against the frozen spec (read what you need): ${FX}/specs/models/{ipc,selector,node,injection,node-id}.md and ${FX}/features/000*/commands/ .
Check:
1. **Verbs & flags**: every flexscope verb the file names must be real (doctor, list-apps, attach, detach, windows, tree, find, node, font, fonts, layer, constraints, ax-diff). Every flag (e.g. find --where/--fields/--limit/--count-only, tree --at/--depth/--fields, node --include, --no-meta/--pretty) must match the spec. Flag \`wrong-flexscope-flag\` for invented or misspelled flags.
2. **Invented defaults**: the spec leaves some flag DEFAULTS and op-name strings unspecified ([NEEDS CLARIFICATION]). The file must NOT state a concrete default for those — it should say "see --help/schema". Flag \`invented-unspecified-default\` for any made-up default value (e.g. a specific --depth or --limit default).
3. **Exit codes**: the file's exit-code claims (0 ok, 2 usage, 3 not-running attach-time, 4 not-attached, 5 stale-node, 6 precondition attach-time, 7 timeout, 8 schema) must match domain.ipc. Flag \`wrong-exit-code\`.
4. **Doctor checks**: the 6 checks (sip, amfi, libval, arm64e-abi, arch, flexmac-built) and "any fail → exit 6" must be correct.
5. **Dual-use posture present & correct** where relevant; SwiftUI-boundary caveat correct.
6. Broken markdown / factual errors.
Cite evidence + fix. Only real problems. Return structured audit.`
}

const privAudits = PRIV_FILES.map(f => () => agent(privPrompt(f), { label: `audit:priv/${f.replace('references/','')}`, phase: 'Audit', schema: AUDIT_SCHEMA }))
const inspAudits = INSP_FILES.map(f => () => agent(inspPrompt(f), { label: `audit:insp/${f.replace('references/','')}`, phase: 'Audit', schema: AUDIT_SCHEMA }))
const audits = await parallel([...privAudits, ...inspAudits])

const CONSISTENCY_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['reciprocalAdvisoryOk','devBoxDistinctionOk','frontmatterOk','missingReferenceFiles','issues','verdict'],
  properties: {
    reciprocalAdvisoryOk: { type: 'boolean', description: 'Do appkit-private-apis, appkit-app-inspector, AND appkit-packaging each carry the cross-referencing distribution advisory (each pointing at the others)?' },
    devBoxDistinctionOk: { type: 'boolean', description: 'Is PrivateHeaderKit correctly described as NOT needing SIP changes (static dump) while flexscope DOES (runtime injection) — never conflated?' },
    frontmatterOk: { type: 'boolean', description: 'Both new SKILL.md have valid frontmatter (name = kebab-case; description starts "Use when"; under 1024 chars)?' },
    missingReferenceFiles: { type: 'array', items: { type: 'string' }, description: 'reference files named in either SKILL.md References table that do not exist on disk.' },
    issues: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['file','issue'], properties: { file: { type: 'string' }, issue: { type: 'string' } } } },
    verdict: { type: 'string' },
  },
}
const consistency = await agent(
`Cross-file consistency for the Phase 3 skills. Read:
- ${PRIV}/SKILL.md and ${PRIV}/references/*.md
- ${INSP}/SKILL.md and ${INSP}/references/*.md
- ${SK}/appkit-packaging/SKILL.md (its "Private APIs & distribution (advisory)" section)
Check: (1) the reciprocal distribution advisory exists in all three (private-apis ↔ app-inspector ↔ packaging); (2) PrivateHeaderKit (static, NO SIP) vs flexscope (runtime injection, SIP/AMFI/LV off) are never conflated; (3) both new SKILL.md frontmatters are valid; (4) every reference file named in either References table exists on disk (list missing + any orphan files not in a table); (5) any contradiction between the two skills. Return the structured report.`,
  { label: 'consistency', phase: 'Consistency', schema: CONSISTENCY_SCHEMA })

return { audits: audits.filter(Boolean), consistency }
