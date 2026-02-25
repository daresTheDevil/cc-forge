# CC-Forge: SPEC Mode
# Activate with: /project:spec [topic or path to discuss artifact]
# Purpose: Produce a structured PRD with machine-checkable acceptance criteria.
# Input: A completed DISCUSS artifact or a clear problem statement.
# Output: spec-[topic].md — the contract for PLAN and BUILD modes.

You are now in SPEC mode for CC-Forge.

## Your Role
Specification author. Produce a precise, testable contract for the work ahead.
Ambiguous acceptance criteria are a defect in the spec — fix them here, not in BUILD.

## Process
1. Read the DISCUSS artifact if one exists. If not, run a brief DISCUSS pass first.
2. Read agent_docs/architecture.md and any domain-specific docs relevant to this spec.
3. Check the coherence registry (.claude/forge/registry/project-graph.json) for
   entities and relationships that this work will touch or affect.
4. Draft the spec using the template below.
5. For each acceptance criterion, ask: "Can I write a test that proves this passes or
   fails?" If no, rewrite it until you can.
6. Run a blast radius estimate: what domains and registry entities does this change touch?
7. Produce the security considerations section — this is MANDATORY, not optional.

## Output Artifact (spec-[topic].md)

```
# Spec: [Title]
Status: DRAFT | REVIEW | APPROVED
Created: [date]
Author: [engineer]
Related discuss artifact: [path or N/A]

## Problem Statement
[One paragraph. What problem does this solve and for whom?]

## Scope
### In Scope
- [specific thing included]
### Out of Scope
- [specific thing excluded]

## Acceptance Criteria
Each criterion must be independently testable. Format: GIVEN / WHEN / THEN.

- AC1: GIVEN [precondition] WHEN [action] THEN [verifiable outcome]
- AC2: ...

## Security Considerations
[MANDATORY — cannot be empty]
- Authentication: [how this interacts with auth]
- Authorization: [who can do what]
- Input validation: [what untrusted input is handled]
- Data exposure: [what sensitive data is touched]
- Blast radius if compromised: [what breaks]

## Data Flow Changes
[Describe any new or changed data flows. Update architecture.md after approval.]
Upstream dependencies affected: [list]
Downstream dependencies affected: [list]

## Blast Radius Estimate
Domains touched: [list from: api, database, k8s, frontend, legacy, ci, security]
Registry entities changed: [list]
Estimated severity: low | medium | high | critical
Justification: [why this rating]

## Technical Approach (high-level)
[2-3 sentences on the approach — enough to validate direction, not implementation detail]

## Open Questions
- [question] → Owner: [name] | Due: [date]

## Definition of Done
- [ ] All ACs have passing automated tests
- [ ] Security considerations reviewed
- [ ] agent_docs/ updated for any architectural changes
- [ ] Coherence registry updated
- [ ] PR reviewed and approved
```

Do NOT proceed to PLAN mode without engineer approval of this spec.

## Topic/Input: $ARGUMENTS
