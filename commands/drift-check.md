# CC-Forge: Drift Check
# Activate with: /project:drift-check [scope: "full" | "domain:[name]"]
# Purpose: Detect divergence between declared state and observed state.
# Runs: automatically pre-build and post-deploy (via hooks). Also available manually.

You are now running a Drift Check for CC-Forge.

## What Drift Means
Drift is any divergence between what the coherence registry says should exist and what
actually exists in the running system. Drift is always a risk signal — it means someone
or something changed the system outside the documented workflow.

## Drift Check Process

### 1. Load Baseline
Read .claude/forge/registry/project-graph.json — this is declared state.
Read the workspace graph at ~/.claude/forge/workspaces/[workspace]/registry/graph.json.

### 2. Observe Actual State (run these and compare to registry)

**k8s drift:**
```bash
kubectl get deployments -n [namespace] -o json    # actual deployments
kubectl get configmaps -n [namespace] -o json     # actual configmaps
kubectl get secrets -n [namespace] --no-headers   # secret names only, never values
helm list -n [namespace]                          # deployed releases vs. expected
```

**Database schema drift (SQL Server):**
```bash
flyway info                                       # migration state — any pending?
# Compare applied migrations to db/migrations/ directory
```

**API drift:**
```bash
# Compare live OpenAPI spec to docs/api/openapi.yaml
# Check for routes that exist in code but not in spec, or vice versa
```

**Dependency drift:**
```bash
bun outdated                                      # package versions vs. lock file
```

**CI drift:**
```bash
# Compare .github/workflows/ to expected pipeline gates in project.toml
```

### 3. Grade Each Finding
For each divergence found, score it:

```
Blast Radius: [low|medium|high|critical] (edges affected in registry)
Security Impact: [none|low|medium|high] (does this affect an auth boundary or secret?)
Recoverability: [immediate|planned|complex] (how hard to restore declared state?)
Overall: [low|medium|high|critical]
```

Use thresholds from project.toml [grading.blast_radius] for edge count classification.

### 4. Report Format

```
# Drift Report: [date] [scope]

## Summary
Total findings: [n]  |  Critical: [n]  |  High: [n]  |  Medium: [n]  |  Low: [n]

## Findings

### DRIFT-001: [Title]
Domain: [k8s | database | api | ci | dependency]
Declared: [what the registry/config says]
Observed: [what actually exists]
Blast Radius: [severity] — [n] registry edges affected
Security Impact: [severity] — [explanation]
Recoverability: [immediate | planned | complex]
Overall Severity: [CRITICAL | HIGH | MEDIUM | LOW]
Recommended Action: [specific action to resolve]

### DRIFT-002: ...

## Auto-Block Recommendation
[List any findings that should block the current build/deploy, per grading config]
```

### 5. On Critical or High Findings
Do NOT proceed with build or deploy. Surface the drift report to the engineer and ask:
- Is this drift intentional? (If yes, update the registry to reflect reality.)
- Does this need to be fixed before proceeding? (Almost always yes for critical.)
- Does this need a break-glass override? (Document it in project.toml if so.)

## Scope: $ARGUMENTS
