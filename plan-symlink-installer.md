# Plan: One-Command Update Architecture
**Date:** 2026-02-25
**Status:** In Progress

## Problem

cc-forge copies all package files to `~/.claude/` at install time, creating a
two-layer architecture where the npm package and deployed files are independent
copies that must be manually kept in sync. Every update requires multiple commands.
Project-level installs (`.claude/forge/`) have no update path at all.

## Goal

```bash
forge update
```

One command updates everything: the global npm package, all global Claude Code
files, and all project-level forge installations across every registered repo.

---

## Architecture

Three scopes, three strategies:

### 1. Global Claude Code Files → Symlinks
`~/.claude/commands/forge--*.md`, `~/.claude/agents/*.md`, hooks, loops, skills

These are owned by cc-forge and must never be hand-edited. Symlink them to the
npm package. When npm updates the package, the symlinks automatically point to
the new version. No redeployment needed.

### 2. User-Owned Config Files → Copy Once
`~/.claude/CLAUDE.md`, `~/.claude/settings.json`, `~/.claude/forge/forge.toml`,
workspace configs

Users customize these. Copy on first install, never touch again on update.

### 3. Project-Level Files → Registry-Driven Update
`.claude/forge/` in each project repo

`forge init` registers the project path in the global registry
(`~/.claude/forge/registry/global-graph.json`). `forge update` reads that
registry and re-runs `forge init --force` in each registered project.

### Result: `forge update` does three things
```
npm install -g cc-forge@latest   ← updates npm package
                                    ← symlinks auto-update global files
forge init --force in each       ← updates all registered projects
  registered project
```

---

## Implementation Tasks

### T001 — Verify Claude Code follows symlinks in ~/.claude/commands/

**Must pass before writing any code.** The entire symlink strategy depends on this.

```bash
PKGDIR="$(npm prefix -g)/lib/node_modules/cc-forge"
ln -sf "${PKGDIR}/commands/discuss.md" ~/.claude/commands/forge--discuss-symtest.md
```

Open Claude Code → type `/forge--discuss-symtest` → confirm it loads and runs.

**Pass:** Command appears and executes normally → proceed with T002.
**Fail:** Claude Code ignores symlinks → symlink approach is invalid, revisit.

Cleanup:
```bash
rm ~/.claude/commands/forge--discuss-symtest.md
```

---

### T002 — Add `install_symlink` to install.sh ✅ COMPLETE 2026-02-25

Add alongside the existing `install_file` function.

```bash
install_symlink() {
  local src="$1"    # path relative to ARTIFACTS_DIR
  local dest="$2"
  local src_path="${ARTIFACTS_DIR}/${src}"

  if [ ! -e "$src_path" ]; then
    printf '[CC-Forge] ❌ Source not found: %s\n' "$src_path" >&2
    return 1
  fi

  mkdir -p "$(dirname "$dest")"

  # Always relink — removes stale copies or outdated symlinks
  rm -f "$dest"
  ln -sf "$src_path" "$dest"
  printf '[CC-Forge] ✅ Linked: %s\n' "$dest"
}
```

Note: unlike `install_file`, `install_symlink` always relinks — no `--force`
flag needed. Package-owned files should always be current.

**Verification:**
```bash
cc-forge
ls -la ~/.claude/commands/forge--recon.md
# Expected: forge--recon.md -> /opt/homebrew/lib/node_modules/cc-forge/commands/recon.md
```

---

### T003 — Convert package-owned installs to symlinks ✅ COMPLETE 2026-02-25

In `install.sh`, replace `install_file` with `install_symlink` for all
package-owned files.

**Convert to symlinks:**
- `commands/*.md` → `~/.claude/commands/forge--*.md`
- `agents/*.md` → `~/.claude/agents/` and `~/.claude/forge/agents/`
- `hooks/*.sh` → `~/.claude/forge/hooks/`
- `loops/*.sh` + `loops/lib/*` → `~/.claude/loops/`
- `skills/**` → `~/.claude/forge/skills/`
- `templates/**` → `~/.claude/forge/templates/`
- `install.sh` → `~/.claude/forge/install.sh`
- `registry/graph-schema.json` → `~/.claude/forge/registry/graph-schema.json`

**Keep as copies (user-owned):**
- `templates/CLAUDE-global.md` → `~/.claude/CLAUDE.md`
- `templates/settings-global.json` → `~/.claude/settings.json`
- `templates/forge.toml` → `~/.claude/forge/forge.toml`
- `templates/workspace-*.toml` → `~/.claude/forge/workspaces/`
- `templates/workspace-registry.toml` → `~/.claude/forge/workspace-registry.toml`

**Verification:**
```bash
cc-forge

# All commands must be symlinks
PKGDIR="$(npm prefix -g)/lib/node_modules/cc-forge"
for f in ~/.claude/commands/forge--*.md; do
  target="$(readlink "$f")"
  [[ "$target" == "${PKGDIR}"* ]] || echo "FAIL: $f → $target"
done

# User config must NOT be symlinks
for f in ~/.claude/CLAUDE.md ~/.claude/settings.json ~/.claude/forge/forge.toml; do
  [ -L "$f" ] && echo "FAIL: $f should be a copy"
done
```

---

### T004 — Register project in global graph on `forge init` ✅ COMPLETE 2026-02-25

When `forge init` runs in a project, write the project path into
`~/.claude/forge/registry/global-graph.json` under a `forge-project` entity.

```bash
register_project() {
  local project_path="$PWD"
  local project_name
  project_name="$(basename "$project_path")"
  local registry="${HOME}/.claude/forge/registry/global-graph.json"

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found — skipping project registration"
    return 0
  fi

  # Add or update entity for this project path
  local updated
  updated="$(jq --arg name "$project_name" --arg path "$project_path" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .entities = (
      [.entities[] | select(.path != $path)] +
      [{"type": "forge-project", "name": $name, "path": $path, "registered_at": $ts}]
    ) |
    .last_updated = $ts
  ' "$registry")"

  printf '%s' "$updated" > "$registry"
  success "Project registered in global registry: $project_name"
}
```

Call `register_project` at the end of the `--project` install path.

**Verification:**
```bash
mkdir -p /tmp/forge-test && cd /tmp/forge-test && git init
forge init
cat ~/.claude/forge/registry/global-graph.json | jq '.entities'
# Should contain an entry with "path": "/tmp/forge-test"
cd ~ && rm -rf /tmp/forge-test
```

---

### T005 — `forge update` iterates registered projects ✅ COMPLETE 2026-02-25

Extend `forge update` in `bin/forge` to re-init all registered projects after
updating the npm package.

```bash
update)
  printf '[CC-Forge] Updating to latest version...\n'
  npm install -g cc-forge@latest

  REGISTRY="${HOME}/.claude/forge/registry/global-graph.json"
  if [ -f "$REGISTRY" ] && command -v jq >/dev/null 2>&1; then
    PROJECTS="$(jq -r '.entities[] | select(.type == "forge-project") | .path' "$REGISTRY" 2>/dev/null)"
    if [ -n "$PROJECTS" ]; then
      printf '[CC-Forge] Updating registered projects...\n'
      while IFS= read -r project_path; do
        if [ -d "$project_path" ]; then
          printf '[CC-Forge] Updating: %s\n' "$project_path"
          (cd "$project_path" && forge init --force --quiet) \
            && printf '[CC-Forge] ✅ %s\n' "$project_path" \
            || printf '[CC-Forge] ⚠️  Failed: %s\n' "$project_path"
        else
          printf '[CC-Forge] ⚠️  Skipping (directory not found): %s\n' "$project_path"
        fi
      done <<< "$PROJECTS"
    fi
  fi

  printf '[CC-Forge] ✅ All done. Run `forge version` to confirm.\n'
  ;;
```

**Verification:**
```bash
# Set up two test projects
mkdir -p /tmp/fp1 /tmp/fp2 && cd /tmp/fp1 && git init && forge init
cd /tmp/fp2 && git init && forge init

# Confirm both are registered
jq '.entities[].path' ~/.claude/forge/registry/global-graph.json

# Run update
forge update

# Both projects should have updated project.toml timestamps
stat /tmp/fp1/.claude/forge/project.toml
stat /tmp/fp2/.claude/forge/project.toml

# Cleanup
rm -rf /tmp/fp1 /tmp/fp2
```

---

### T006 — Handle stale project entries (deregister on `forge deinit`) ✅ COMPLETE 2026-02-25

Add a `forge deinit` command (or auto-cleanup in `forge update`) that removes
project entries whose directories no longer exist.

```bash
deinit)
  REGISTRY="${HOME}/.claude/forge/registry/global-graph.json"
  if [ -f "$REGISTRY" ] && command -v jq >/dev/null 2>&1; then
    updated="$(jq --arg path "$PWD" '
      .entities = [.entities[] | select(.path != $path)]
    ' "$REGISTRY")"
    printf '%s' "$updated" > "$REGISTRY"
    success "Project removed from global registry: $(basename "$PWD")"
  fi
  ;;
```

Auto-cleanup in `forge update`: already handled by the `[ -d "$project_path" ]`
check with a warning. Optionally prompt to remove stale entries.

**Verification:**
```bash
mkdir -p /tmp/fp-gone && cd /tmp/fp-gone && git init && forge init
jq '.entities[].path' ~/.claude/forge/registry/global-graph.json
# Shows /tmp/fp-gone

rm -rf /tmp/fp-gone
forge update
# Should print: ⚠️  Skipping (directory not found): /tmp/fp-gone
```

---

### T007 — Update README ✅ COMPLETE 2026-02-25

Document the new flow clearly.

```markdown
## Installing

```bash
npm install -g cc-forge
cc-forge          # sets up ~/.claude/ — run once
```

## Adding to a project

```bash
cd your-project
forge init
```

## Updating everything

```bash
forge update
```

Updates cc-forge globally and re-initializes all registered projects.
```

---

## End-to-End Verification

```bash
# Fresh install
npm install -g cc-forge@latest && cc-forge

# Confirm global commands are symlinks
PKGDIR="$(npm prefix -g)/lib/node_modules/cc-forge"
FAIL=0
for f in ~/.claude/commands/forge--*.md; do
  target="$(readlink "$f" 2>/dev/null)"
  [[ "$target" == "${PKGDIR}"* ]] || { echo "FAIL (not symlink): $f"; FAIL=1; }
done
[ $FAIL -eq 0 ] && echo "✅ All global commands are symlinks"

# Init two projects and confirm registration
mkdir -p /tmp/fp1 /tmp/fp2
cd /tmp/fp1 && git init -q && forge init --quiet
cd /tmp/fp2 && git init -q && forge init --quiet
COUNT="$(jq '.entities | length' ~/.claude/forge/registry/global-graph.json)"
echo "Registered projects: $COUNT (expected ≥ 2)"

# Run update — should touch both projects
forge update

# Manual step: open Claude Code, run /forge--recon, confirm it loads
echo "Manual: verify /forge--recon loads in Claude Code"

# Cleanup
rm -rf /tmp/fp1 /tmp/fp2
```

---

## Release Plan

| Version | Tasks | Description |
|---|---|---|
| `0.1.5` | T001, T002, T003 | Symlink-based global files |
| `0.1.6` | T004, T005 | Registry registration + `forge update` project iteration |
| `0.1.7` | T006, T007 | `forge deinit` + README |

Collapse into fewer releases if tasks complete cleanly together.

---

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Claude Code doesn't follow symlinks | Low | T001 must pass before any code |
| Symlink target disappears if npm uninstalls | Low | `forge update` reinstalls npm first |
| User edits a symlinked command file | Medium | Editor will warn "editing a symlink" — add note to README |
| Project moved/renamed breaks registry | Medium | T006 auto-cleanup on update handles this |
| `forge init --force` in update overwrites user project config | High risk if not handled | `--force` must only overwrite package-owned files, never user config |
