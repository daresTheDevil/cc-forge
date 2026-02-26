## FORGE AGENT HANDOFF
From: {AGENT_NAME}
To: {NEXT_AGENT}
Timestamp: {ISO8601}
Plan: {plan-file.md | none}
Task: {TASK_ID | none}

### Context
{1-3 sentences: what was this agent's scope and what did it establish?}

### Findings
{Bulleted list of key discoveries, constraints, decisions made}

### Files Modified
{Repo-relative paths — empty list if read-only agent}

### Open Questions
{Items the receiving agent must resolve — empty list if none}

### Recommendations
{Specific actionable direction for the next agent}

### Signal
```json
{
  "from": "{AGENT_NAME}",
  "to": "{NEXT_AGENT}",
  "task_id": "{TASK_ID or null}",
  "status": "complete",
  "files_modified": [],
  "open_questions": 0,
  "blocking": false
}
```
<!-- status valid values: "complete" | "partial" | "blocked" -->
