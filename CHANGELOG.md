# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-02-26

### Changed
- **Install architecture rewritten** — global file deployment is now explicit (`forge setup`) instead of happening silently in `postinstall`; matches the universal pattern used by eslint, husky, changesets, and every other major Node CLI tool
- **`install.sh --global` uses copies, not symlinks** — all files deployed to `~/.claude/` are now plain copies; symlinks broke silently when the source npm package was removed, updated, or installed via `pnpm dlx` (which cleans up its temp dir on exit)
- **`bin/cc-forge` rewritten as a bootstrapper** — `npx cc-forge` now does exactly two things: `npm install -g cc-forge@VERSION` (permanent install) then `forge setup` (file deployment); removed the heredoc forge script and shell profile PATH manipulation
- **`forge update` simplified** — no longer hunts for `install.sh` via `npm root -g`; calls `forge setup --force` directly after the npm install

### Added
- **`forge setup`** — new subcommand; deploys global files from the npm package to `~/.claude/`; `--force` overwrites existing files (used by `forge update`)

### Removed
- **`scripts.postinstall`** from `package.json` — pnpm v10 and Bun both disable postinstall by default; the hook was silently skipped for a significant portion of installs
- **`~/.claude/forge/bin/forge`** deploy — npm's `bin` field handles the binary; the separate copy in `~/.claude/forge/bin/` was redundant and fought with the npm-managed binary on updates

### Fixed
- `pnpm dlx cc-forge` no longer creates dangling symlinks to a temp dir that no longer exists after the command exits
- `forge update` no longer fails when the npm package moves between global install paths (e.g. switching between npm and nvm node versions)

## [0.2.2] - 2026-02-26

### Fixed
- `forge update` and `postinstall` were passing `--quiet` to `install.sh` — flag does not exist, caused update to abort

## [0.2.1] - 2026-02-26

### Fixed
- `forge update` now runs `install.sh --global --force` after the npm install so hooks, commands, templates, agents, and the forge binary are all propagated — previously only the npm package was updated
- `install.sh --global` now symlinks `bin/forge` to `~/.claude/forge/bin/forge`, replacing any stale binary left by older bootstrap methods
- `npm install -g cc-forge` now auto-runs `install.sh --global` via postinstall — no separate bootstrap step required

## [0.2.0] - 2026-02-26

### Added
- **`/forge--learn`** — session pattern extraction command; analyzes the current session for non-trivial solutions and writes structured skill files to the project memory directory; respects 180-line MEMORY.md threshold with archive housekeeping; never extracts credentials, tokens, or connection strings
- **Inter-agent handoff schema** — `templates/agent-handoff.md` structured contract for handoffs between build agents; JSON Signal block with `blocking` field distinguishes blocked builds from normal task transitions
- **Agent handoff emission in build** — `commands/build.md` now instructs BUILD mode to write `.forge/handoffs/agent-{TASK_ID}-{timestamp}.md` after every task; build loop halts and prints explicit message on `blocking: true`; separate from the JSON signal (machine reads signal, human/next agent reads handoff)
- **Agent handoff detection on continue** — `commands/continue.md` Step 1 surfaces blocked `agent-*.md` handoffs before the session SITREP; non-blocking handoffs noted as recent task activity without interrupting the resume flow
- **`hooks/context-handoff.sh`** — background script triggered by statusline threshold; writes minimal state handoff to `.forge/handoffs/handoff-{timestamp}.md` and registers `~/.claude/pending-resume`; fully silent (all output to `/dev/null`), always exits 0, never blocks the render path
- **Context threshold detection in `statusline.sh`** — parses `used_percentage` from stdin JSON; displays inline `⚠ CTX N%` warning; triggers one-shot background context-handoff at configurable threshold (default `CONTEXT_THRESHOLD=70`); one-shot flag (`.forge/logs/context-threshold-triggered`) prevents re-firing within the same session; numeric guard and full error suppression protect the render path
- **Model frontmatter** — `model:` alias added to commands (`sec` → `opus`, `plan` → `opus`, `recon` → `haiku`) and all five agents (`security-reviewer` → `opus`, all others → `sonnet`); Model Selection reference table added to `agent_docs/architecture.md`

### Changed
- **`hooks/session-end.sh`** — full rewrite; writes machine-readable JSON state to `.forge/logs/last-session.json` (ended\_at, branch, uncommitted\_changes, forge\_phase, forge\_task) and a `learn-pending` flag file; removes all placeholder stub-appending behaviour; gracefully degrades when jq is absent
- **`hooks/pre-compact.sh`** — new hook; captures branch, uncommitted count, and recent dirty files to `.forge/logs/pre-compact-state.json` before context window auto-compaction; produces zero stdout (runs on the render path)
- **`templates/settings.json`** — wires `PreCompact` hook; adds two new `SessionStart` entries (last-session digest banner + learn-pending notice with auto-cleanup); removes dead `~/.golem/` hook references that silently failed on every hook event; moves PostToolUse log target from `.golem/logs/` to `.forge/logs/file-changes.log`
- **`hooks/statusline.sh`** — promoted from standalone file to cc-forge package; `install.sh --global` now symlinks it to `~/.claude/statusline.sh` so statusline updates ship with forge upgrades
- **`commands/build.md` output** — mode-aware output instructions: rich human-readable completion table in interactive/slash-command mode; JSON-only schema contract for headless `build.sh` invocations (where `--json-schema` enforces structured output at the API level regardless)

### Fixed
- Dead `~/.golem/` hook references in `templates/settings.json` that silently failed on every `PreToolUse` and `PostToolUse` event since the golem directory does not exist

## [0.1.6] - 2026-02-25

### Added
- **Global graph harvest** — `/forge--recon` now runs a harvest pass after populating the project graph, classifying entities by kind and proposing globally-relevant ones (databases, external services, CI/CD, infra) for promotion to `~/.claude/forge/registry/global-graph.json`
- **Harvest conflict detection** — `harvest-merge.sh` implements three-way merge: identical entities are skipped, metadata differences surface a diff and exit without writing, existing constraints are always preserved and never dropped
- **PRR shared infrastructure seeded** — 13 Pearl River Resort shared infrastructure entities pre-loaded into global graph including Oracle SWS (with READ ONLY account-level constraint), all casino SQL Server sources, Microsoft Entra ID, LDAP, UKG REST API, Harbor registry, microk8s cluster, and Woodpecker CI
- **Cross-project blast radius** — `/forge--blast` now reads the global graph alongside the project graph; identifies all registered repos that reference a shared entity so blast radius analysis works across projects

## [0.1.5] - 2026-02-25

### Added
- **One-command update** — `forge update` now updates the npm package AND re-initializes all registered projects in one step; no `--force` flag needed
- **Project registry** — `forge init` registers each project path in `~/.claude/forge/registry/global-graph.json` so `forge update` knows what to update
- **`forge deinit`** — removes the current project from the global registry
- **Symlink-based global install** — package-owned files (`commands/`, `agents/`, `hooks/`, `loops/`, `skills/`, `templates/`) are now symlinked to the npm package instead of copied; updating npm automatically updates all global files
- **`context: fork` on `/forge--build`** — build command now runs in an isolated subagent with no conversation history, giving a clean context on every invocation
- **Smarter `test:coverage` warning** — `forge init` now detects vitest, jest, or nuxt and suggests the exact fix command instead of a `[command]` placeholder

### Fixed
- `forge update` previously used `pnpm dlx`/`npx` which ran from a temp dir and did not persist; now uses `npm install -g`
- `forge version` now reads from `package.json` instead of the stale `forge.toml`
- Symlink resolution in `bin/forge` — `PACKAGE_DIR` now uses `realpath` to resolve the npm symlink before computing paths, fixing global installs where `dirname` walked to `/opt/homebrew` instead of the package directory
- Stale `/recon` reference in `commands/blast.md` updated to `/forge--recon`
- `forge init` next-steps output corrected from `/recon` to `/forge--recon`

## [0.1.1] - 2026-02-25

### Added
- `forge build` auto-detects newest `plan-*.md` when no file specified
- `forge build [plan.md]` and `forge improve [--scope]` subcommands on the `forge` CLI
- Developer workflow journeys in README (onboarding, feature build, incident response, continuous improvement)
- npm badges (version, downloads, license, node version)

### Changed
- Restructured flat file layout into subdirectories (`commands/`, `agents/`, `hooks/`, `loops/`, `skills/`, `templates/`)
- Renamed project from `forge-cc` to `cc-forge` throughout
- README reframed around engineering discipline; coherence engine gets its own section
- Inspired By section with Ralph Loop and get-shit-done links
- `bin/forge` and `bin/cc-forge` stale reference fixes

## [0.1.0] - 2026-02-25

### Added

- **Workflow modes** — `/forge--discuss`, `/forge--spec`, `/forge--plan`, `/forge--build`, `/forge--improve` slash commands covering the full development lifecycle
- **Parallel code review** — `/forge--review` spawns Code (Sonnet) + Security (Opus) + Performance (Sonnet) agents simultaneously with aggregated `[AUTO]` / `[REVIEW]` / `[HALT]` certainty grading
- **Security audit** — `/forge--sec` full scan of code, dependencies, secrets, and infrastructure; persists findings to `.forge/security.json` scorecard
- **Blast radius analysis** — `/forge--blast` maps every entity and relationship affected by a proposed change using `project-graph.json` before any cross-domain modification
- **Coherence engine** — `project-graph.json` registry tracks entities and relationships across code, infra, security, docs, and CI; populated by `/forge--recon`, read by all other modes
- **Drift detection** — `/forge--drift-check` audits every `agent_docs/` file against its declared `drift_check` target and surfaces divergence
- **Forge Loop** — headless shell-controlled continuous improvement loop (`loops/forge-loop.sh`); Claude executes single iterations and emits structured JSON signals, shell decides whether to iterate
- **Build Loop** — headless TDD build executor (`loops/build.sh`); sequences tasks from a plan file, gates on passing tests between tasks, threads session context across all tasks via `--resume`
- **Claude Code hooks** — `SessionStart`, `PreToolUse(Bash)`, `PreToolUse(kubectl)`, `PostToolUse(Write/Edit)`, `Stop` hooks auto-fire on every action
- **Git hooks** — pre-commit blocks secrets, unsafe migrations, typecheck and lint failures; commit-msg enforces conventional commit format
- **Session management** — `/forge--handoff` and `/forge--continue` for structured cross-session state capture and resume
- **Incident response** — `/forge--fire` activates `TRIAGE → ISOLATE → DIAGNOSE → PATCH → VERIFY → DEBRIEF` protocol with auto-generated post-mortem
- **Operations commands** — `/forge--recon`, `/forge--diagnose`, `/forge--drift-check`, `/forge--simplify`, `/forge--document`
- **Domain skills** — SQL Server, Oracle, IBM i / AS400, Nuxt 3, legacy PHP; loaded progressively from `~/.claude/forge/skills/`
- **Three-layer config cascade** — `forge.toml` (machine) → `workspace.toml` (domain) → `project.toml` (repo); projects can only tighten constraints, never loosen them
- **Global and project install modes** — `install.sh --global` bootstraps the machine, `install.sh --project [workspace-id]` sets up a repo with full directory structure, hooks, and agent docs templates
- **Agent docs templates** — `architecture.md`, `database-schema.md`, `api-patterns.md`, `k8s-layout.md`, `legacy-guide.md`, `testing-guide.md`, `runbooks/env-var-drift.md` — all with staleness headers and `drift_check` fields
- **Structured directory layout** — `commands/`, `agents/`, `agent_docs/`, `hooks/`, `loops/`, `skills/`, `templates/` replacing flat file structure
