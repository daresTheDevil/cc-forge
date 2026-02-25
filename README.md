# CC-Forge

**A coherence engine for developers who manage complex stacks alone.**

You're running microk8s, two databases, a Nuxt frontend, a legacy PHP service, and a handful of Python/Node APIs. You're the architect, the security team, the code reviewer, and the on-call engineer — all at once. Things drift. Docs fall behind. Tests get skipped. Nobody catches the blast radius before a refactor lands sideways.

CC-Forge is the engineering discipline system you never had time to build yourself. It layers structured workflow modes, parallel AI code review, automated security enforcement, and a continuous improvement loop directly into your Claude Code environment — all driven by slash commands and shell scripts you actually control.

---

## What It Does

| Without CC-Forge | With CC-Forge |
|---|---|
| Spec lives in your head | Structured PRD with testable acceptance criteria |
| Code review = you re-reading your own code | Parallel agents: Code + Security (Opus) + Performance |
| Security = vibes | Pre-commit hooks block secrets and unsafe migrations |
| Docs drift from reality | Coherence registry tracks every entity and relationship |
| "I'll refactor later" | Continuous Forge Loop — measurable delta every iteration |
| Context lost between sessions | Structured handoffs, session state, progress logs |

---

## Install

```bash
npm install -g cc-forge
cc-forge --global
```

Or clone and install from source:

```bash
git clone https://github.com/yourusername/cc-forge
cd cc-forge
/opt/homebrew/bin/bash install.sh --global
```

Then add it to a project:

```bash
cd your-project
cc-forge --project applications
```

### Requirements

- [Claude Code CLI](https://docs.anthropic.com/claude-code) — authenticated and on PATH
- bash 4.0+ (`brew install bash` on macOS)
- `jq` (`brew install jq`)
- `dasel` (`brew install dasel`) — TOML parsing for config cascade
- `git-secrets` or `trufflehog` — secret scanning (pre-commit hook degrades without one)

---

## How It Works

CC-Forge installs three layers into your environment:

```
~/.claude/                          # Global layer
├── CLAUDE.md                       # Non-negotiable gates, enforced every session
├── commands/forge--*.md            # Slash commands — the workflow modes
├── agents/                         # Parallel review specialists
├── forge/                          # Config cascade root
│   ├── forge.toml                  # Machine-wide baseline
│   └── workspaces/{id}/            # Domain standards (applications | platform | data)
└── loops/                          # Headless CLI loop controllers

{project}/                          # Project layer
├── CLAUDE.md                       # Project-specific overrides (tightens, never loosens)
├── .claude/
│   ├── forge/project.toml          # This repo's config — checked into git
│   ├── hooks/                      # Claude Code hooks — auto-fire on every action
│   └── agent_docs/                 # Progressive disclosure context for Claude
└── .forge/                         # Runtime state — gitignored
    ├── state.json                  # Current phase and build progress
    ├── security.json               # Persistent security scorecard
    └── reviews/                    # Timestamped review reports
```

Config inherits in cascade: `forge.toml` → `workspace.toml` → `project.toml`. Projects can only tighten constraints, never loosen them.

---

## Slash Commands

All commands use the `forge--` prefix — unambiguous, no conflicts with Claude built-ins.

### Workflow Modes

| Command | What It Does |
|---|---|
| `/forge--discuss` | Explore the problem. Surface assumptions, identify unknowns, expose hidden constraints before writing a line of code. |
| `/forge--spec` | Produce a structured PRD with testable acceptance criteria. The contract between intent and implementation. |
| `/forge--plan` | Break the spec into an implementation graph with explicit task dependencies and build order. |
| `/forge--build` | TDD implementation — write the failing test first, always. Invoked headless via `loops/build.sh`. |
| `/forge--improve` | Single Forge Loop iteration: measure → identify top opportunity → improve → verify → emit signal. |

### Review & Security

| Command | What It Does |
|---|---|
| `/forge--review` | Spawn parallel review agents simultaneously: Code (Sonnet) + Security (Opus) + Performance (Sonnet). Aggregated findings with certainty grades: `[AUTO]` `[REVIEW]` `[HALT]`. |
| `/forge--sec` | Full security audit. Scans code, dependencies, secrets, and infrastructure. Updates `.forge/security.json` scorecard. `HALT` findings stop all other work. |
| `/forge--blast` | Blast radius analysis before any cross-domain change. Reads `project-graph.json` to map every entity and relationship affected. Run before significant refactors. |

### Operations

| Command | What It Does |
|---|---|
| `/forge--recon` | Rapid codebase orientation. Populates `project-graph.json` and `agent_docs/`. Run first on any new project. |
| `/forge--diagnose` | Systematic microk8s triage: env vars → secrets → config → connectivity. Structured runbook, not vibes. |
| `/forge--fire` | Incident response. Activates `TRIAGE → ISOLATE → DIAGNOSE → PATCH → VERIFY → DEBRIEF`. Speed over perfection. Auto-generates post-mortem. |
| `/forge--drift-check` | Verify docs and registry match current codebase state. Every `agent_docs/` file declares a `drift_check` target — this audits them all. |

### Session Management

| Command | What It Does |
|---|---|
| `/forge--handoff` | Capture full session state. Writes structured handoff to `.forge/handoffs/` so the next session resumes with full context. |
| `/forge--continue` | Resume from a handoff document. Loads state, presents a situation report, confirms before touching anything. |
| `/forge--document` | Full documentation pass — inline code docs, markdown docs, changelog, README. |
| `/forge--simplify` | Complexity reduction pass. Forced order: delete → merge → replace → clarify. Never adds, only removes. |

---

## The Forge Loop

The continuous improvement loop runs headless from your terminal — Claude Code is not the loop controller, the shell is:

```bash
~/.claude/loops/forge-loop.sh --scope src/
```

Each iteration, Claude measures the codebase, identifies the highest-impact improvement opportunity, makes the change, verifies it, and emits a structured JSON signal. The shell reads the signal and decides whether to iterate again.

```
bash forge-loop.sh
  → claude -p "..." --output-format json --json-schema improve-signal-schema.json
  ← { "status": "loop|complete|blocked|error", "delta": 0.08, ... }
  → iterate or exit
```

The `--json-schema` flag enforces the signal contract structurally — Claude cannot emit free text, extraction paths are deterministic, and a crashed run can be resumed from the last `session_id`.

---

## Hooks

CC-Forge installs Claude Code hooks that fire automatically:

| Hook | Trigger | What It Does |
|---|---|---|
| `SessionStart` | Every session open | Surfaces phase, security score, and last 20 lines of progress log |
| `PreToolUse(Bash)` | Before any bash command | Blocks destructive commands (`rm -rf`, `DROP TABLE`, `git reset --hard`, etc.) |
| `PreToolUse(kubectl)` | Before any deploy | Validates all `secretKeyRef` and `configMapKeyRef` references exist |
| `PostToolUse(Write/Edit)` | After any file write | Auto-format + append to `file-changes.log` |
| `Stop` | Session end | Appends progress stub to `claude-progress.txt` |
| `git commit` | Pre-commit | Blocks secrets, fails unsafe migrations, enforces typecheck and lint |
| `git commit-msg` | Commit message | Enforces conventional commit format |

---

## Stack

CC-Forge is built for heterogeneous stacks. Domain skills ship with the package:

- **Databases:** SQL Server (T-SQL, Flyway), Oracle (sequences, bind variables, wallet), IBM i / AS400 (EBCDIC, file locking, ODBC)
- **Frontend:** Nuxt 3 (SSR, composables, server routes)
- **Legacy:** PHP (characterization tests, PDO, safe refactor patterns)

Skills live in `~/.claude/forge/skills/` and are loaded progressively — Claude reads the relevant skill file before working with that technology.

---

## Config

```toml
# .claude/forge/project.toml
[project]
id = "my-service"
name = "My Service"
workspace = "applications"

[workflow.improve]
improvement_threshold = 0.05   # minimum delta to keep looping
max_iterations = 10

[enforcement]
require_tests = true
block_destructive_db = true
```

Three-layer cascade: `forge.toml` (machine) → `workspace.toml` (domain) → `project.toml` (repo). Projects can tighten any constraint but cannot loosen machine-wide or workspace-level gates.

---

## License

MIT
