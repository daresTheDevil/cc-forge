# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
