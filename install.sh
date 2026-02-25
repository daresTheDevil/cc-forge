#!/usr/bin/env bash
# ~/.claude/forge/install.sh
# CC-Forge Install Script
#
# Usage:
#   install.sh --global              Install/update global CC-Forge files to ~/.claude/
#   install.sh --project             Install project structure in current directory
#   install.sh --project [ws-id]     Install with specific workspace ID
#   install.sh --global --force      Overwrite existing files (backup made first)
#   install.sh --project --force     Overwrite existing project files
#
# Exit codes:
#   0 = success
#   1 = dependency check failed or hard error
#   2 = already installed (non-force mode) — not an error, just a notice

set -euo pipefail

# ---------------------------------------------------------------------------
# Script location — all paths relative to this file
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORGE_CC_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# If this script is deployed to ~/.claude/forge/, cc-forge artifacts are
# in the same directory as this script.
# If running from the cc-forge/ repo directory, artifacts are in the same dir.
if [ -f "${SCRIPT_DIR}/docs/implementation.md" ]; then
  # Running from cc-forge/ repo
  ARTIFACTS_DIR="${SCRIPT_DIR}"
elif [ -f "${FORGE_CC_DIR}/docs/implementation.md" ]; then
  ARTIFACTS_DIR="${FORGE_CC_DIR}"
else
  # Fallback: same directory as this script (deployed mode)
  ARTIFACTS_DIR="${SCRIPT_DIR}"
fi

# ---------------------------------------------------------------------------
# Colors (degraded gracefully if not supported)
# ---------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1)    YELLOW=$(tput setaf 3)
  GREEN=$(tput setaf 2)  CYAN=$(tput setaf 6)
  BOLD=$(tput bold)      RESET=$(tput sgr0)
else
  RED="" YELLOW="" GREEN="" CYAN="" BOLD="" RESET=""
fi

info()    { printf '%s[CC-Forge]%s %s\n' "$CYAN"   "$RESET" "$*"; }
success() { printf '%s[CC-Forge]%s ✅ %s\n' "$GREEN"  "$RESET" "$*"; }
warn()    { printf '%s[CC-Forge]%s ⚠️  %s\n' "$YELLOW" "$RESET" "$*"; }
error()   { printf '%s[CC-Forge]%s ❌ %s\n' "$RED"    "$RESET" "$*" >&2; }
header()  { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
MODE=""
WORKSPACE_ID=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global)   MODE="global";  shift ;;
    --project)  MODE="project"; shift ;;
    --force)    FORCE=true;     shift ;;
    --help|-h)
      printf 'Usage:\n'
      printf '  install.sh --global            Install global CC-Forge files to ~/.claude/\n'
      printf '  install.sh --project [ws-id]   Install project structure in current directory\n'
      printf '  install.sh --force             Overwrite existing files (backup first)\n'
      exit 0
      ;;
    *)
      if [ "$MODE" = "project" ] && [ -z "$WORKSPACE_ID" ]; then
        WORKSPACE_ID="$1"
        shift
      else
        error "Unknown argument: $1"
        exit 1
      fi
      ;;
  esac
done

if [ -z "$MODE" ]; then
  error "Mode required: --global or --project"
  printf 'Run: install.sh --help\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Dependency checks (hard requirements — no partial installs)
# ---------------------------------------------------------------------------
header "Checking dependencies..."

DEPS_OK=true

check_dep() {
  local cmd="$1"
  local install_hint="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    success "$cmd found ($(command -v "$cmd"))"
  else
    error "$cmd not found. Install: $install_hint"
    DEPS_OK=false
  fi
}

check_dep "jq"     "brew install jq"
check_dep "dasel"  "brew install dasel  (or: go install github.com/TomWright/dasel/v2/cmd/dasel@latest)"
check_dep "claude" "Install Claude Code CLI: npm install -g @anthropic-ai/claude-code"

# Check bash version (4.0+ required for arrays and mapfile)
BASH_MAJOR="${BASH_VERSINFO[0]:-0}"
if [ "$BASH_MAJOR" -lt 4 ]; then
  error "bash 4.0+ required (current: ${BASH_VERSION}). Install: brew install bash"
  DEPS_OK=false
else
  success "bash ${BASH_VERSION} ≥ 4.0"
fi

if [ "$DEPS_OK" = false ]; then
  error "One or more required dependencies are missing. Install them and try again."
  exit 1
fi

success "All hard dependencies satisfied."

# Secret scanner check — soft warning (pre-commit hook degrades gracefully without one,
# but silent degradation is worse than a loud warning at install time)
header "Checking secret scanners (soft requirement)..."
SCANNER_FOUND=false
if command -v git-secrets >/dev/null 2>&1; then
  success "git-secrets found ($(command -v git-secrets))"
  SCANNER_FOUND=true
fi
if command -v trufflehog >/dev/null 2>&1; then
  success "trufflehog found ($(command -v trufflehog))"
  SCANNER_FOUND=true
fi
if [ "$SCANNER_FOUND" = false ]; then
  warn "No secret scanner found (git-secrets or trufflehog)."
  warn "  The pre-commit hook will skip secret scanning until one is installed."
  warn "  Install options:"
  warn "    brew install git-secrets  (then: git secrets --install -f)"
  warn "    brew install trufflehog   (or: pip install trufflehog)"
fi

# ---------------------------------------------------------------------------
# Install helper: copy with backup
# ---------------------------------------------------------------------------
install_file() {
  local src="$1"       # source file path relative to ARTIFACTS_DIR
  local dest="$2"      # destination absolute path
  local mode="${3:-}"  # optional chmod mode (e.g., "755")

  if [ ! -f "${ARTIFACTS_DIR}/${src}" ]; then
    warn "Source file not found, skipping: ${src}"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  if [ -f "$dest" ]; then
    if [ "$FORCE" = true ]; then
      local backup="${dest}.bak.$(date '+%Y%m%d')"
      cp "$dest" "$backup"
      info "Backed up existing file: $backup"
      cp "${ARTIFACTS_DIR}/${src}" "$dest"
      success "Updated: $dest"
    else
      info "Skipping (already exists, use --force to overwrite): $dest"
      return 0
    fi
  else
    cp "${ARTIFACTS_DIR}/${src}" "$dest"
    success "Installed: $dest"
  fi

  if [ -n "$mode" ]; then
    chmod "$mode" "$dest"
  fi
}

# ---------------------------------------------------------------------------
# Install helper: create file with content if it doesn't exist
# ---------------------------------------------------------------------------
install_seed() {
  local dest="$1"
  local content="$2"

  if [ -f "$dest" ] && [ "$FORCE" = false ]; then
    info "Skipping (already exists): $dest"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  printf '%s\n' "$content" > "$dest"
  success "Created: $dest"
}

# ---------------------------------------------------------------------------
# GLOBAL INSTALL
# ---------------------------------------------------------------------------
if [ "$MODE" = "global" ]; then
  header "Installing CC-Forge globally to ~/.claude/"

  CLAUDE_DIR="${HOME}/.claude"
  FORGE_DIR="${CLAUDE_DIR}/forge"
  LOOPS_DIR="${CLAUDE_DIR}/loops"
  COMMANDS_DIR="${CLAUDE_DIR}/commands"
  AGENTS_DIR="${CLAUDE_DIR}/agents"
  SKILLS_DIR="${FORGE_DIR}/skills"

  # Core directories
  mkdir -p "${FORGE_DIR}/registry" \
           "${FORGE_DIR}/workspaces/platform" \
           "${FORGE_DIR}/workspaces/applications" \
           "${FORGE_DIR}/workspaces/data" \
           "${LOOPS_DIR}/lib" \
           "${COMMANDS_DIR}" \
           "${AGENTS_DIR}" \
           "${SKILLS_DIR}/databases" \
           "${SKILLS_DIR}/frameworks"

  header "Global config files..."
  install_file "templates/CLAUDE-global.md"            "${CLAUDE_DIR}/CLAUDE.md"
  install_file "templates/settings-global.json"        "${CLAUDE_DIR}/settings.json"
  install_file "templates/forge.toml"                  "${FORGE_DIR}/forge.toml"
  install_file "templates/workspace-registry.toml"     "${FORGE_DIR}/workspace-registry.toml"
  install_file "templates/workspace-platform.toml"     "${FORGE_DIR}/workspaces/platform/workspace.toml"
  install_file "templates/workspace-applications.toml" "${FORGE_DIR}/workspaces/applications/workspace.toml"
  install_file "templates/workspace-data.toml"         "${FORGE_DIR}/workspaces/data/workspace.toml"

  header "Registry seed and schema..."
  install_seed "${FORGE_DIR}/registry/global-graph.json" \
    '{"version":"1.0","last_updated":null,"entities":[],"relationships":[]}'
  install_file "templates/registry-graph-schema.json" "${FORGE_DIR}/registry/graph-schema.json"

  header "Loop scripts..."
  install_file "loops/lib/improve-signal-schema.json" "${LOOPS_DIR}/lib/improve-signal-schema.json"
  install_file "loops/lib/build-signal-schema.json"   "${LOOPS_DIR}/lib/build-signal-schema.json"
  install_file "loops/lib/signals.sh"                 "${LOOPS_DIR}/lib/signals.sh"           "644"
  install_file "loops/forge-loop.sh"                  "${LOOPS_DIR}/forge-loop.sh"             "755"
  install_file "loops/build.sh"                       "${LOOPS_DIR}/build.sh"                  "755"

  header "Slash commands (forge-- prefix: double-dash separates namespace from command)..."
  install_file "commands/discuss.md"     "${COMMANDS_DIR}/forge--discuss.md"
  install_file "commands/spec.md"        "${COMMANDS_DIR}/forge--spec.md"
  install_file "commands/plan.md"        "${COMMANDS_DIR}/forge--plan.md"
  install_file "commands/build.md"       "${COMMANDS_DIR}/forge--build.md"
  install_file "commands/improve.md"     "${COMMANDS_DIR}/forge--improve.md"
  install_file "commands/review.md"      "${COMMANDS_DIR}/forge--review.md"
  install_file "commands/fire.md"        "${COMMANDS_DIR}/forge--fire.md"
  install_file "commands/blast.md"       "${COMMANDS_DIR}/forge--blast.md"
  install_file "commands/recon.md"       "${COMMANDS_DIR}/forge--recon.md"
  install_file "commands/sec.md"         "${COMMANDS_DIR}/forge--sec.md"
  install_file "commands/simplify.md"    "${COMMANDS_DIR}/forge--simplify.md"
  install_file "commands/diagnose.md"    "${COMMANDS_DIR}/forge--diagnose.md"
  install_file "commands/drift-check.md" "${COMMANDS_DIR}/forge--drift-check.md"
  install_file "commands/handoff.md"     "${COMMANDS_DIR}/forge--handoff.md"
  install_file "commands/continue.md"    "${COMMANDS_DIR}/forge--continue.md"
  install_file "commands/document.md"    "${COMMANDS_DIR}/forge--document.md"

  header "Domain skills..."
  install_file "skills/databases/ibmi.md"   "${SKILLS_DIR}/databases/ibmi.md"
  install_file "skills/databases/mssql.md"  "${SKILLS_DIR}/databases/mssql.md"
  install_file "skills/databases/oracle.md" "${SKILLS_DIR}/databases/oracle.md"
  install_file "skills/frameworks/nuxt.md"  "${SKILLS_DIR}/frameworks/nuxt.md"
  install_file "skills/frameworks/php.md"   "${SKILLS_DIR}/frameworks/php.md"

  header "Install script (self-deploy)..."
  install_file "install.sh" "${FORGE_DIR}/install.sh" "755"

  header "Project template bundle (needed by deployed install.sh --project)..."
  # When install.sh runs from ~/.claude/forge/ instead of the cc-forge source dir,
  # it looks for template files relative to itself. Bundle them here so project
  # installs work from anywhere without needing the cc-forge source repo.
  install_file "templates/project.toml"              "${FORGE_DIR}/templates/project.toml"
  install_file "templates/CLAUDE-project.md"         "${FORGE_DIR}/templates/CLAUDE-project.md"
  install_file "templates/settings.json"             "${FORGE_DIR}/templates/settings.json"
  install_file "templates/forge-state.json"          "${FORGE_DIR}/templates/forge-state.json"
  install_file "templates/forge-security.json"       "${FORGE_DIR}/templates/forge-security.json"
  install_file "templates/registry-project-graph.json" "${FORGE_DIR}/templates/registry-project-graph.json"
  install_file "hooks/pre-commit.sh"                 "${FORGE_DIR}/hooks/pre-commit.sh"
  install_file "hooks/post-edit.sh"                  "${FORGE_DIR}/hooks/post-edit.sh"
  install_file "hooks/pre-deploy.sh"                 "${FORGE_DIR}/hooks/pre-deploy.sh"
  install_file "hooks/session-end.sh"                "${FORGE_DIR}/hooks/session-end.sh"
  install_file "hooks/validate-bash.sh"              "${FORGE_DIR}/hooks/validate-bash.sh"
  install_file "hooks/commit-msg.sh"                 "${FORGE_DIR}/hooks/commit-msg.sh"
  install_file "agents/db-explorer.md"               "${FORGE_DIR}/agents/db-explorer.md"
  install_file "agents/test-writer.md"               "${FORGE_DIR}/agents/test-writer.md"
  install_file "agents/code-reviewer.md"             "${FORGE_DIR}/agents/code-reviewer.md"
  install_file "agents/security-reviewer.md"         "${FORGE_DIR}/agents/security-reviewer.md"
  install_file "agents/performance-reviewer.md"      "${FORGE_DIR}/agents/performance-reviewer.md"
  install_file "agent_docs/architecture.md"          "${FORGE_DIR}/agent_docs/architecture.md"
  install_file "agent_docs/database-schema.md"       "${FORGE_DIR}/agent_docs/database-schema.md"
  install_file "agent_docs/api-patterns.md"          "${FORGE_DIR}/agent_docs/api-patterns.md"
  install_file "agent_docs/k8s-layout.md"            "${FORGE_DIR}/agent_docs/k8s-layout.md"
  install_file "agent_docs/legacy-guide.md"          "${FORGE_DIR}/agent_docs/legacy-guide.md"
  install_file "agent_docs/testing-guide.md"         "${FORGE_DIR}/agent_docs/testing-guide.md"
  install_file "agent_docs/runbooks/env-var-drift.md" "${FORGE_DIR}/agent_docs/runbooks/env-var-drift.md"

  header "Global agents..."
  install_file "agents/db-explorer.md"          "${AGENTS_DIR}/db-explorer.md"
  install_file "agents/test-writer.md"          "${AGENTS_DIR}/test-writer.md"
  install_file "agents/code-reviewer.md"        "${AGENTS_DIR}/code-reviewer.md"
  install_file "agents/security-reviewer.md"    "${AGENTS_DIR}/security-reviewer.md"
  install_file "agents/performance-reviewer.md" "${AGENTS_DIR}/performance-reviewer.md"

  header "Global install complete."
  printf '\n%sNext steps:%s\n' "$BOLD" "$RESET"
  printf '  1. Verify: claude --version\n'
  printf '  2. Run in a project: install.sh --project [workspace-id]\n'
  printf '  3. Open Claude Code in the project and run /forge--recon\n'

fi

# ---------------------------------------------------------------------------
# PROJECT INSTALL
# ---------------------------------------------------------------------------
if [ "$MODE" = "project" ]; then
  header "Installing CC-Forge project structure in: $(pwd)"

  PROJECT_CLAUDE_DIR=".claude"
  FORGE_PROJ_DIR="${PROJECT_CLAUDE_DIR}/forge"
  HOOKS_DIR="${PROJECT_CLAUDE_DIR}/hooks"
  AGENT_DOCS_DIR="${PROJECT_CLAUDE_DIR}/agent_docs"
  REGISTRY_DIR="${FORGE_PROJ_DIR}/registry"
  RUNTIME_DIR=".forge"

  # Create directory structure
  mkdir -p "${FORGE_PROJ_DIR}" \
           "${REGISTRY_DIR}" \
           "${HOOKS_DIR}" \
           "${AGENT_DOCS_DIR}/runbooks" \
           "${RUNTIME_DIR}/handoffs" \
           "${RUNTIME_DIR}/history" \
           "${RUNTIME_DIR}/metrics" \
           "${RUNTIME_DIR}/reviews" \
           "${RUNTIME_DIR}/logs" \
           "${RUNTIME_DIR}/runbooks"

  # Resolve template source — prefer bundled templates in deployed location,
  # fall back to repo subdirectory
  if [ -d "${ARTIFACTS_DIR}/templates" ]; then
    TMPL_DIR="${ARTIFACTS_DIR}/templates"
  else
    TMPL_DIR="${ARTIFACTS_DIR}"
  fi

  header "Project config..."
  install_file "templates/CLAUDE-project.md" "CLAUDE.md"
  install_file "templates/project.toml"      "${FORGE_PROJ_DIR}/project.toml"
  install_file "templates/settings.json"     "${PROJECT_CLAUDE_DIR}/settings.json"

  header "Runtime state (first-time only)..."
  install_seed "${RUNTIME_DIR}/state.json"    '{"phase":"idle","build":{"current_task":null,"completed_tasks":[],"completed":false}}'
  install_seed "${RUNTIME_DIR}/security.json" '{"scores":{"code":100,"deps":100,"secrets":100,"infra":100,"overall":100},"last_audit":null,"findings":{"code":{"critical":0,"high":0,"medium":0,"low":0},"deps":{"critical_vulns":0,"high_vulns":0,"outdated_major":0},"secrets":{"rotation_schedule":{}},"infra":{"pods_without_resource_limits":0,"pods_without_security_context":0,"network_policies_missing":false,"rbac_violations":0}}}'

  header "Registry seed..."
  install_seed "${REGISTRY_DIR}/project-graph.json" \
    '{"version":"1.0","last_updated":null,"entities":[],"relationships":[]}'

  header "Hooks..."
  install_file "hooks/pre-commit.sh"    "${HOOKS_DIR}/pre-commit.sh"  "755"
  install_file "hooks/post-edit.sh"     "${HOOKS_DIR}/post-edit.sh"   "755"
  install_file "hooks/pre-deploy.sh"    "${HOOKS_DIR}/pre-deploy.sh"  "755"
  install_file "hooks/session-end.sh"   "${HOOKS_DIR}/session-end.sh" "755"
  install_file "hooks/validate-bash.sh" "${HOOKS_DIR}/validate-bash.sh" "755"
  install_file "hooks/commit-msg.sh"    "${HOOKS_DIR}/commit-msg.sh"  "755"

  header "Agent docs templates..."
  install_file "agent_docs/architecture.md"          "${AGENT_DOCS_DIR}/architecture.md"
  install_file "agent_docs/database-schema.md"       "${AGENT_DOCS_DIR}/database-schema.md"
  install_file "agent_docs/api-patterns.md"          "${AGENT_DOCS_DIR}/api-patterns.md"
  install_file "agent_docs/k8s-layout.md"            "${AGENT_DOCS_DIR}/k8s-layout.md"
  install_file "agent_docs/legacy-guide.md"          "${AGENT_DOCS_DIR}/legacy-guide.md"
  install_file "agent_docs/testing-guide.md"         "${AGENT_DOCS_DIR}/testing-guide.md"
  install_file "agent_docs/runbooks/env-var-drift.md" "${AGENT_DOCS_DIR}/runbooks/env-var-drift.md"

  header "Project agents..."
  install_file "agents/db-explorer.md"          "${PROJECT_CLAUDE_DIR}/agents/db-explorer.md"
  install_file "agents/test-writer.md"          "${PROJECT_CLAUDE_DIR}/agents/test-writer.md"
  install_file "agents/code-reviewer.md"        "${PROJECT_CLAUDE_DIR}/agents/code-reviewer.md"
  install_file "agents/security-reviewer.md"    "${PROJECT_CLAUDE_DIR}/agents/security-reviewer.md"
  install_file "agents/performance-reviewer.md" "${PROJECT_CLAUDE_DIR}/agents/performance-reviewer.md"

  # Create initial progress file
  if [ ! -f "claude-progress.txt" ]; then
    {
      printf '# CC-Forge Progress Log\n'
      printf 'Project: %s\n' "$(basename "$(pwd)")"
      printf 'Initialized: %s\n' "$(date '+%Y-%m-%d')"
      printf '\n'
    } > "claude-progress.txt"
    success "Created: claude-progress.txt"
  fi

  # Update workspace ID in project.toml if provided
  if [ -n "$WORKSPACE_ID" ] && [ -f "${FORGE_PROJ_DIR}/project.toml" ] && command -v dasel >/dev/null 2>&1; then
    dasel put -f "${FORGE_PROJ_DIR}/project.toml" -t string "workspace" "$WORKSPACE_ID" 2>/dev/null \
      && success "Workspace set to: $WORKSPACE_ID" \
      || warn "Could not set workspace ID — update ${FORGE_PROJ_DIR}/project.toml manually"
  fi

  # Auto-install the commit-msg git hook if a .git directory exists
  if [ -d ".git" ]; then
    GIT_HOOKS_DIR=".git/hooks"
    COMMIT_MSG_SRC="${HOOKS_DIR}/commit-msg.sh"
    COMMIT_MSG_DEST="${GIT_HOOKS_DIR}/commit-msg"
    if [ -f "$COMMIT_MSG_SRC" ]; then
      if [ -f "$COMMIT_MSG_DEST" ] && [ "$FORCE" = false ]; then
        info "Skipping git hook (already exists, use --force to overwrite): $COMMIT_MSG_DEST"
      else
        if [ -f "$COMMIT_MSG_DEST" ] && [ "$FORCE" = true ]; then
          cp "$COMMIT_MSG_DEST" "${COMMIT_MSG_DEST}.bak.$(date '+%Y%m%d')"
        fi
        cp "$COMMIT_MSG_SRC" "$COMMIT_MSG_DEST"
        chmod 755 "$COMMIT_MSG_DEST"
        success "Installed git hook: $COMMIT_MSG_DEST"
      fi
    fi
  else
    info "No .git directory found — skipping commit-msg git hook (run after git init if needed)"
  fi

  # Add .forge/ to .gitignore if not already there
  if [ -f ".gitignore" ]; then
    if ! grep -q "^\.forge/$" ".gitignore" 2>/dev/null; then
      printf '\n# CC-Forge runtime state (non-config)\n.forge/\n' >> ".gitignore"
      success "Added .forge/ to .gitignore"
    fi
  fi

  # ---------------------------------------------------------------------------
  # Measurement tool pre-flight (warn, not fail)
  # ---------------------------------------------------------------------------
  header "Measurement tool pre-flight (for Forge Loop metrics)..."
  if [ -f "package.json" ] && command -v jq >/dev/null 2>&1; then
    SCRIPTS=$(jq -r '.scripts | keys | .[]' package.json 2>/dev/null || echo "")
    for SCRIPT in typecheck lint "test:coverage"; do
      if printf '%s\n' "$SCRIPTS" | grep -qx "$SCRIPT"; then
        success "npm script found: $SCRIPT"
      else
        warn "npm script missing: $SCRIPT — Forge Loop metrics will be degraded"
        if [ "$SCRIPT" = "test:coverage" ]; then
          # Detect test framework and suggest the right command
          if jq -e '.dependencies["vitest"] // .devDependencies["vitest"]' package.json >/dev/null 2>&1; then
            warn "  Fix: add to package.json scripts: \"test:coverage\": \"vitest run --coverage\""
          elif jq -e '.dependencies["jest"] // .devDependencies["jest"]' package.json >/dev/null 2>&1; then
            warn "  Fix: add to package.json scripts: \"test:coverage\": \"jest --coverage\""
          elif jq -e '.dependencies["nuxt"] // .devDependencies["nuxt"]' package.json >/dev/null 2>&1; then
            warn "  Fix (Nuxt): install vitest + coverage, then add:"
            warn "    npm install -D vitest @nuxt/test-utils @vitest/coverage-v8"
            warn "    \"test:coverage\": \"vitest run --coverage\""
          else
            warn "  Fix: add to package.json scripts: \"test:coverage\": \"<your-test-runner> --coverage\""
          fi
        else
          warn "  Add to package.json scripts: \"$SCRIPT\": \"[command]\""
        fi
      fi
    done
  fi

  header "Project install complete."
  printf '\n%sNext steps:%s\n' "$BOLD" "$RESET"
  printf '  1. Review and customize: %s\n' "${FORGE_PROJ_DIR}/project.toml"
  printf '  2. Open Claude Code in this project\n'
  printf '  3. Run /forge--recon to populate agent_docs/ and project-graph.json\n'
  if [ ! -d ".git" ]; then
    printf '  4. After git init, install the commit-msg hook:\n'
    printf '     cp %s .git/hooks/commit-msg\n' "${HOOKS_DIR}/commit-msg.sh"
    printf '     chmod +x .git/hooks/commit-msg\n'
  fi
fi

header "Done."
exit 0
