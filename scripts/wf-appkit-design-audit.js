export const meta = {
  name: 'appkit-design-symbol-audit',
  description: 'Adversarial symbol + grounding audit of the appkit-design SKILL.md and its 9 references',
  phases: [
    { title: 'Audit', detail: 'per-file skeptic: verify every symbol, HIG URL, and corpus ref' },
    { title: 'Consistency', detail: 'cross-file house-style + reference-table integrity' },
  ],
}

const SKILL_DIR = '/Users/orion/Developer/Templates/skills/mac-dev-skills/plugins/appkit/skills/appkit-design'
const FILES = [
  'SKILL.md',
  'references/app-type-anchors.md',
  'references/control-selection.md',
  'references/layout-and-spacing.md',
  'references/semantic-color.md',
  'references/typography.md',
  'references/liquid-glass.md',
  'references/window-sizing.md',
  'references/accessibility.md',
  'references/design-anti-patterns.md',
]

const AUDIT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['file', 'symbolsChecked', 'symbolIssues', 'higIssues', 'corpusRefIssues', 'verdict'],
  properties: {
    file: { type: 'string' },
    symbolsChecked: { type: 'number', description: 'How many distinct AppKit/Foundation symbols you verified with sdk-api.' },
    symbolIssues: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['symbol', 'kind', 'evidence', 'fix'],
        properties: {
          symbol: { type: 'string' },
          kind: { type: 'string', enum: ['not-found', 'wrong-version-gate', 'deprecated-as-current', 'wrong-signature', 'other'] },
          evidence: { type: 'string', description: 'What the file claims vs what sdk-api returned.' },
          fix: { type: 'string', description: 'The exact corrected symbol/version/signature.' },
        },
      },
    },
    higIssues: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['url', 'kind', 'evidence'],
        properties: {
          url: { type: 'string' },
          kind: { type: 'string', enum: ['404-or-unreachable', 'malformed', 'not-a-hig-page'] },
          evidence: { type: 'string' },
        },
      },
    },
    corpusRefIssues: {
      type: 'array',
      items: {
        type: 'object', additionalProperties: false,
        required: ['id', 'evidence'],
        properties: { id: { type: 'string' }, evidence: { type: 'string' } },
      },
    },
    verdict: { type: 'string', description: '"clean" if nothing to fix, else a 1-2 sentence summary of the must-fix issues.' },
  },
}

function auditPrompt(file) {
  return `You are a hostile AppKit API auditor. Assume the author of this file HALLUCINATED symbols, invented version numbers, and fabricated HIG URLs. Your job is to prove each claim or flag it. "Looks plausible" is not "verified."

FILE: ${SKILL_DIR}/${file}

Do this:
1. Read the file.
2. Extract every distinct AppKit/Foundation symbol it names (types, members, enum cases, initializers). A fast candidate sweep:
   \`grep -oE '\\bNS[A-Za-z]+(\\.[a-zA-Z]+(\\([a-zA-Z:_]*\\))?)?' ${SKILL_DIR}/${file} | sort -u\`
   plus any symbol in code fences the grep misses.
3. Verify EACH with the installed tool: \`~/.local/bin/sdk-api check '<Symbol>'\` (or \`availability <Symbol>\` for version claims, \`members <Type>\` to find the real member). Flag:
   - not-found: the file names a symbol that does not resolve ANYWHERE (a hallucination).
   - wrong-version-gate: the file states/implies a min-macOS that disagrees with sdk-api (e.g. claims 26.0 but it's 27.0), OR uses a 26.0+ symbol with NO \`if #available\` gate.
   - deprecated-as-current: sdk-api marks it deprecated but the file presents it as the modern choice.
   - wrong-signature: e.g. \`NSFont.preferredFont(forTextStyle:)\` WITHOUT \`options:\` (the AppKit signature requires options:), or any member with the wrong argument labels.

   CRITICAL — avoid these false positives (sdk-api has known resolution rules; a tool "not-found" is NOT automatically a hallucination):
   - **Protocol-inherited members.** sdk-api resolves a member under the PROTOCOL that declares it, not the conforming class. So \`NSView.setAccessibilityIdentifier(_:)\` returns not-found, but the call \`view.setAccessibilityIdentifier("x")\` is VALID because it's declared on \`NSAccessibilityProtocol\` (NSView conforms). Before flagging a \`Type.member\` as not-found, re-check the protocol-qualified form (try \`NSAccessibilityProtocol.<member>\`, \`NSAppearanceCustomization.effectiveAppearance\`, \`NSAnimatablePropertyContainer.*\`) and \`~/.local/bin/sdk-search get <related-id>\` keySymbols. Only flag if it resolves NOWHERE under any owner.
   - **Bare instance-call syntax.** A snippet writing \`someView.fittingSize\` or \`control.setAccessibilityLabel(...)\` is verified by confirming the member exists on the type OR a protocol it conforms to — not by demanding \`NSView.fittingSize\` literally resolve if the real owner differs.
4. For every HIG URL in the file, WebFetch it. NOTE: the macOS HIG pages are JS-rendered SPAs — a real page returns HTTP 200 with essentially only a \`<title>\`/no body. **Title-only is NOT a defect** (the page exists). Flag ONLY a genuine 404/unreachable, a malformed URL, or a URL not under \`https://developer.apple.com/design/human-interface-guidelines/\`. Do not flag a reachable page for lacking body text.
5. For every corpus pattern id the file references (kebab-case ids like \`tableview-view-based-reuse\`), confirm it exists: \`~/.local/bin/sdk-search get <id> >/dev/null 2>&1; echo $?\` (0 = exists). Flag ids that don't resolve.

Be precise: cite what the file says and what the tool returned. Do NOT flag non-AppKit tokens (Swift keywords, your own grep noise), protocol-inherited members that resolve under their protocol owner, or HIG pages that are merely title-only. Only real, fixable problems. Return the structured audit.`
}

const audits = await parallel(
  FILES.map((f) => () => agent(auditPrompt(f), { label: `audit:${f.replace('references/', '')}`, phase: 'Audit', schema: AUDIT_SCHEMA }))
)

const CONSISTENCY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['missingReferenceFiles', 'brokenCrossRefs', 'styleIssues', 'contradictions', 'verdict'],
  properties: {
    missingReferenceFiles: { type: 'array', items: { type: 'string' }, description: 'Files named in the SKILL.md References table that do not exist on disk.' },
    brokenCrossRefs: {
      type: 'array',
      items: { type: 'object', additionalProperties: false, required: ['from', 'to', 'evidence'],
        properties: { from: { type: 'string' }, to: { type: 'string' }, evidence: { type: 'string' } } },
    },
    styleIssues: {
      type: 'array',
      items: { type: 'object', additionalProperties: false, required: ['file', 'issue'],
        properties: { file: { type: 'string' }, issue: { type: 'string' } } },
    },
    contradictions: {
      type: 'array',
      items: { type: 'object', additionalProperties: false, required: ['files', 'evidence'],
        properties: { files: { type: 'string' }, evidence: { type: 'string' } } },
    },
    verdict: { type: 'string' },
  },
}

const consistency = await agent(
  `Review the appkit-design skill for cross-file integrity and house-style consistency. Read all of these:
${FILES.map((f) => `- ${SKILL_DIR}/${f}`).join('\n')}

Check and report:
1. missingReferenceFiles: every file named in SKILL.md's "References" table must exist under ${SKILL_DIR}/references/. List any that don't (also list reference files on disk NOT in the table).
2. brokenCrossRefs: any \`references/<x>.md\` or skill name cross-reference that points at a nonexistent target.
3. styleIssues: files that break house style — must each have an H1 title + one-line purpose, be table-heavy with at least one GOOD (and ideally a BAD) code example, cite a HIG URL near the top, and run roughly 60–160 lines. Flag files that are bare, missing the HIG citation, or wildly off-length.
4. contradictions: any place two files give conflicting guidance (e.g. different recommended control for the same requirement, or a symbol spelled differently).

Be concrete with file names and quotes. Return the structured report.`,
  { label: 'consistency', phase: 'Consistency', schema: CONSISTENCY_SCHEMA }
)

return { audits: audits.filter(Boolean), consistency }
