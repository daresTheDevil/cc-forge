---
description: Full documentation pass — inline code docs, markdown docs, changelog, README. Human-readable output. Separate from /forge--recon which produces machine-readable coherence maps.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# CC-Forge Document — Documentation Pass

You are running a documentation generation pass. Goal: make the codebase
understandable to humans (developers, stakeholders, future maintainers).

This is NOT /forge--recon. Recon produces agent_docs/ and project-graph.json
for Claude. This produces docs/, CHANGELOG.md, and inline code comments for
humans. Different outputs, different audiences, different rules.

## Rules (non-negotiable)

- **Code behavior must not change** — documentation only. No refactoring.
- **No empty placeholders** — only document things that exist and have real behavior.
- **Preserve accurate docs** — update what has drifted; archive what's removed.
- **No test files, lock files, node_modules, generated files** — skip them entirely.
- **Verify tests still pass after inline docs** — documentation can break things if
  you accidentally modify a string in a test assertion. Run tests after Phase 2.

## Options

Parse `$ARGUMENTS` for flags:

- `--path <dir>` — scope to a subdirectory (e.g., `--path src/services/auth`)
- `--inline-only` — only Phase 2 (skip markdown generation)
- `--markdown-only` — only Phase 3+ (skip inline docs)
- `--dry-run` — report what would be done without making any changes
- `--scope <phase>` — run only named phase (e.g., `--scope changelog`)

If no flags: run the full pass.

---

## Phase 1: Detect Project Type

Read `.claude/forge/project.toml` for the declared stack. Cross-check against:
- `package.json` (JS/TS projects: framework, test runner, build tool)
- `pyproject.toml` or `requirements.txt` (Python)
- `composer.json` (PHP)

Determine:
- **Language(s):** typescript, javascript, python, php
- **Framework:** nuxt, vue, next, react, none
- **Doc standard:** TSDoc (`/** */` + `@param`, `@returns`, `@example`), JSDoc,
  Google-style docstrings (Python), SQL `--` comments
- **Docs output path:** from `project.toml` `[docs] path` if set, else `docs/`
- **Test command:** from `project.toml` `[stack.testing] runner` or package.json scripts

Report detection results. Stop if detection fails — don't guess.

---

## Phase 2: Inline Documentation (skip with `--markdown-only`)

Find source files in scope. For each file:

1. Read it completely
2. Add a file-level header comment explaining its purpose and role
3. Document non-obvious functions, methods, classes, and types
4. Apply the correct standard for the detected language:
   - **TypeScript:** TSDoc — `/** @param x - description @returns description @example */`
   - **JavaScript (ESM):** JSDoc `/** ... */`
   - **Vue/Nuxt SFCs:** JSDoc in `<script setup>`, `<!-- -->` only for non-obvious template sections
   - **Python:** Google-style docstrings with Args/Returns/Raises sections
   - **PHP:** PHPDoc `/** @param @return @throws */`
   - **SQL:** `--` comment blocks on CREATE TABLE, stored procedures, views
5. Skip trivially obvious code (getters, self-documenting one-liners)
6. Document complex conditionals and non-obvious "why" decisions

After documenting, run the project's test command:
```bash
# From project.toml or package.json
bun run test    # or pytest, phpunit, etc.
```
If tests fail: revert the changes that broke them and note which files were skipped.

---

## Phase 3: Markdown Documentation (skip with `--inline-only`)

Generate or update project documentation in the docs directory.

### Directory Structure

```
{docsPath}/
  index.md              — project overview, what this is and why it exists
  architecture.md       — system design, service connections (based on agent_docs/architecture.md)
  getting-started.md    — setup, install, prerequisites for a new developer
  configuration.md      — all config options explained (project.toml, env vars)
  modules/
    {module-name}.md    — one per major module or service
  api/
    {resource}.md       — API reference (if project has HTTP endpoints)
  database/
    schema.md           — schema overview with relationships (based on agent_docs/database-schema.md)
  guides/
    setup.md            — dev environment setup
    {workflow}.md       — project-specific how-tos
  deprecated/
    {old-thing}.md      — archived docs with deprecation date
```

### Frontmatter (required on every file)

```yaml
---
title: "Page Title"
description: "One sentence description"
last_updated: "YYYY-MM-DD"
---
```

### Rules

- Cross-link between docs where relevant
- Explain behavior and usage — do not dump source code into markdown docs
- Base architecture/schema docs on what's in agent_docs/ (single source of truth)
- If agent_docs/ docs are stale (last_verified > 14 days), note it in the generated doc

---

## Phase 4: Changelog

Generate or update `CHANGELOG.md` at the project root from git history.

```bash
git log --oneline --no-merges $(git describe --tags --abbrev=0 2>/dev/null)..HEAD
```

Format using Keep a Changelog convention:
```markdown
## [Unreleased]

### Added
- {user-visible new capability}

### Changed
- {user-visible change to existing behavior}

### Fixed
- {bug that was fixed, described from user perspective}
```

- Write in plain language for non-technical audiences
- No jargon — "Improved how player sessions are tracked" not "Refactored session state machine"
- Only include sections that have entries
- Preserve any existing content below [Unreleased]

---

## Phase 5: README

Generate or update `README.md` at the project root.

Read the existing README if it exists — preserve any user-written content
outside of these sections:
- Project name and one-line description
- Quick start / install instructions
- Links to docs/ for detailed documentation

Do NOT overwrite the entire README. Edit surgically around existing content.

---

## Phase 6: Archive Deprecated

Check if any documented modules or APIs have been removed from the codebase.

If a doc exists in `docs/modules/{name}.md` but the code it documents no longer
exists (check project-graph.json entities and actual file paths):
- Move to `docs/deprecated/{name}.md`
- Add frontmatter: `deprecated_date: {today}` and `replaced_by: {name or empty}`

---

## Phase 7: Sync agent_docs/ (Forge-specific)

After generating human docs, check if the process revealed any drift in agent_docs/:

- If you updated `docs/architecture.md` based on new findings, update
  `agent_docs/architecture.md` too (and reset `last_verified` date)
- If `docs/api/{resource}.md` reveals patterns not in `agent_docs/api-patterns.md`,
  add them
- Run a quick drift check: do the docs you just wrote match what's in agent_docs/?
  If not, update agent_docs/ to match — it's the source of truth for Claude's context

---

## Phase 8: Summary

Present a summary of what was done (or what would be done with `--dry-run`):

```
## Document Pass Complete

Phase 2 (inline docs):
  - {N} source files documented
  - {N} files skipped (trivial / already documented)
  - Tests: {passed / N failed / not run}

Phase 3 (markdown docs):
  - {N} docs created
  - {N} docs updated
  - {N} docs archived to deprecated/

Phase 4 (changelog): {created / updated / skipped}
Phase 5 (README):    {created / updated / skipped}
Phase 7 (agent_docs sync): {N docs updated / none needed}

Docs output: {docsPath}/
```

---

## Begin

Start by reading `.claude/forge/project.toml` and detecting the project type (Phase 1).
Report detection results. If `--dry-run` is set, announce it before proceeding.
