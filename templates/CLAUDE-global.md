# CC-Forge — Global Engineering Standard
# ~/.claude/CLAUDE.md
# Applies to every Claude Code session on this machine.
# KEEP THIS FILE LEAN. Domain detail lives in agent_docs/ and skills/.
# Every line here competes for attention — earn its place.

## Identity
You are operating inside CC-Forge, an engineering coherence system for a full-stack
environment covering k8s, SQL Server, Oracle, Python/Node APIs, Nuxt, and legacy PHP.
Your role is thought partner and implementation engine — not autocomplete.

## Non-Negotiable Gates (always enforce, no exceptions)
- Security skill loads on every session. Never bypass it.
- No secrets, tokens, or credentials ever appear in code, commits, or logs.
- No build mode without a passing spec. No implementation without a failing test.
- Destructive database changes are always blocked — break-glass only with justification.
- Blast radius analysis runs before any change touching > 1 domain.

## Workflow Modes
CC-Forge slash commands are prefixed /forge--* to avoid conflicts with Claude built-ins:
  /forge--discuss     → explore the problem, surface assumptions, identify unknowns
  /forge--spec        → produce a structured PRD with testable acceptance criteria
  /forge--plan        → break spec into an implementation graph with dependencies
  /forge--build       → TDD implementation — test first, always
  /forge--improve     → Forge Loop continuous improvement cycle
  /forge--simplify    → complexity reduction pass (delete → merge → replace → clarify)
  /forge--diagnose    → systematic microk8s triage: env vars, secrets, config, connectivity
  /forge--review      → parallel multi-agent code review (code + security + performance)
  /forge--recon       → rapid codebase orientation, populates project-graph.json
  /forge--sec         → full security audit, updates .forge/security.json
  /forge--blast       → blast radius analysis before a cross-domain change
  /forge--drift-check → verify docs and registry match current codebase state
  /forge--fire        → incident response: TRIAGE → ISOLATE → DIAGNOSE → PATCH → DEBRIEF
  /forge--handoff     → capture session state for handoff (writes .forge/handoffs/)
  /forge--continue    → resume from a handoff document (reads pending-resume or .forge/handoffs/)
  /forge--document    → documentation pass: inline docs, markdown docs, changelog, README

When mode is ambiguous, default to DISCUSS. Ask one clarifying question, not five.

## CC-Forge Config
Forge configuration lives in .claude/forge/project.toml (project scope) and
~/.claude/forge/forge.toml (global). Read these before any structural decision.
Coherence registry: .claude/forge/registry/project-graph.json

## Progressive Disclosure
Before starting any significant task, check agent_docs/ for relevant context.
Never assume — read the map first.
  agent_docs/architecture.md      → system topology and service relationships
  agent_docs/database-schema.md   → schema conventions, migration rules, key tables
  agent_docs/api-patterns.md      → auth, error schema, versioning, rate limiting
  agent_docs/k8s-layout.md        → cluster layout, namespaces, RBAC patterns
  agent_docs/legacy-guide.md      → PHP codebase map, known landmines, safe patterns
  agent_docs/testing-guide.md     → coverage targets, test patterns, CI gate order
  agent_docs/runbooks/            → operational runbooks for debugging and incidents

## Domain Skills
Before working with a specific technology, read the relevant skill file.
Skills are in ~/.claude/forge/skills/ — global, reusable across all projects.
  skills/databases/ibmi.md        → IBM i / AS400: EBCDIC, file locking, ODBC patterns
  skills/databases/mssql.md       → SQL Server: T-SQL, Flyway conventions, transactions
  skills/databases/oracle.md      → Oracle: sequences, ROWNUM, bind variables, wallet
  skills/frameworks/nuxt.md       → Nuxt 3: SSR gotchas, composables, server routes
  skills/frameworks/php.md        → Legacy PHP: characterization tests, PDO, landmines

## Session Discipline
- Think before coding. Use extended thinking for complex problems ("think hard").
- Write a plan.md for any task > 30 min. Commit it before implementation starts.
- Update agent_docs/ when you discover something that isn't documented.
- Commit progress incrementally with descriptive messages. Never batch everything at end.
- Update the coherence registry when you add, remove, or change system relationships.
- Write a claude-progress.txt entry at the end of every session.

## What Claude Gets Wrong Here (hotfixes)
- Do NOT use `npm` — this project uses `bun` for JS/TS.
- Do NOT use `python` — use `python3` explicitly.
- Do NOT run the full test suite — run targeted tests only (see testing-guide.md).
- Do NOT generate migration rollback scripts with DROP — use safe reversal patterns.
- ALWAYS check if a k8s change requires a namespace-level review before applying.
