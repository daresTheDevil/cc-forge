---
last_verified: YYYY-MM-DD
last_verified_by: [session-id or engineer-name]
drift_check: compare declared env vars in .claude/agent_docs/k8s-layout.md against live secretKeyRef/configMapKeyRef blocks in deploy/helm/templates/**/*.yaml
---

# Runbook: Environment Variable Drift

**Classification:** Operational Runbook
**Trigger:** Pod CrashLoopBackOff, missing env var errors in logs, deployment failures after config changes, unexpected app behavior after infra changes
**Related:** `/diagnose` command (Phase 3 automates this), `hooks/pre-deploy.sh` (validates secretKeyRef at deploy time)

---

## What Is Env Var Drift

An app expects a set of environment variables. Over time, the actual runtime config diverges from what the app expects. This happens when:

- A secret key is renamed or deleted (`secretKeyRef` references a key that no longer exists)
- A ConfigMap is updated but not all consumers are notified
- A new env var is added to app code but not to the deployment manifest
- A staging URL is promoted to production (value drift, not key drift)
- A secret is rotated with a key name change instead of a value update

The `/diagnose` command runs a superset of this runbook automatically. Use this runbook directly when you need a focused env var audit without a full cluster triage.

---

## Step 1: Ground Truth — What Does the Running Container Actually See?

```bash
# The authoritative source: what the process has at runtime
microk8s kubectl exec -n $NAMESPACE $POD -- env | sort

# If the container is crashing, use a debug sidecar instead
microk8s kubectl debug -it $POD -n $NAMESPACE --image=busybox --copy-to=debug-pod -- env | sort
```

---

## Step 2: What Does the Deployment Declare?

```bash
# Inline env vars in the deployment spec
microk8s kubectl get deployment $APP -n $NAMESPACE \
  -o jsonpath='{.spec.template.spec.containers[*].env}' | jq .

# ConfigMap and Secret bulk references (envFrom)
microk8s kubectl get deployment $APP -n $NAMESPACE \
  -o jsonpath='{.spec.template.spec.containers[*].envFrom}' | jq .

# Specific secret key references (secretKeyRef)
microk8s kubectl get deployment $APP -n $NAMESPACE \
  -o jsonpath='{.spec.template.spec.containers[*].env[?(@.valueFrom.secretKeyRef)]}' | jq .

# Specific configmap key references (configMapKeyRef)
microk8s kubectl get deployment $APP -n $NAMESPACE \
  -o jsonpath='{.spec.template.spec.containers[*].env[?(@.valueFrom.configMapKeyRef)]}' | jq .
```

---

## Step 3: What Do the ConfigMaps Contain?

```bash
# List all ConfigMaps in namespace
microk8s kubectl get configmaps -n $NAMESPACE

# Dump all ConfigMap data (non-secret, safe to view)
for cm in $(microk8s kubectl get configmaps -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== ConfigMap: $cm ==="
  microk8s kubectl get configmap "$cm" -n $NAMESPACE -o jsonpath='{.data}' | jq .
  echo ""
done
```

---

## Step 4: What Do the Secrets Declare? (Keys Only — Never Dump Values)

```bash
# List secrets and their key names (NOT values — values stay encrypted)
for secret in $(microk8s kubectl get secrets -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== Secret: $secret (keys only) ==="
  microk8s kubectl get secret "$secret" -n $NAMESPACE -o jsonpath='{.data}' | jq 'keys'
  echo ""
done
```

---

## Step 5: What Does the App Expect?

```bash
# Check .env.example / .env.template in the repo (source of truth for expected vars)
cat .env.example 2>/dev/null || cat .env.template 2>/dev/null || echo "No .env template found"

# Node/TypeScript: env vars the app reads
grep -rE "process\.env\.[A-Z_]+" src/ --include="*.ts" --include="*.js" \
  | grep -oE "process\.env\.[A-Z_]+" | sort -u

# Python: env vars the app reads
grep -rE "os\.environ|os\.getenv" src/ --include="*.py" \
  | grep -oE '(os\.environ\[|os\.getenv\()["\x27][A-Z_]+["\x27]' | sort -u

# PHP: env vars the app reads
grep -rE "\$_ENV\[|getenv\(" . --include="*.php" \
  | grep -oE "(getenv\(|_ENV\[)['\"][A-Z_a-z_]+['\"]" | sort -u
```

---

## Step 6: Build the Drift Matrix

For every expected variable, complete this table:

| Variable Name   | Expected By App | In ConfigMap | In Secret | Actually Set | Match? |
|-----------------|-----------------|--------------|-----------|--------------|--------|
| DATABASE_URL    | yes             | no           | yes       | yes          | ✅     |
| API_KEY         | yes             | no           | yes       | no           | ❌     |
| LOG_LEVEL       | yes             | yes          | no        | yes          | ✅     |
| STALE_VAR       | no              | yes          | no        | yes          | ⚠️ extra|

**Flags:**
- ❌ Expected but not set → likely cause of the production bug — fix this first
- ⚠️ Set but not expected → stale config, possible confusion source, clean up
- 🔄 Set to wrong value → value drift (staging URL in production, wrong DB)
- 🔒 Secret key referenced but secret doesn't have that key → silent failure at startup

---

## Step 7: Fix and Verify

```bash
# After fixing (e.g., adding missing key to a Secret):
microk8s kubectl rollout restart deployment/$APP -n $NAMESPACE

# Verify pod reaches Running state
microk8s kubectl rollout status deployment/$APP -n $NAMESPACE

# Verify health endpoint responds
microk8s kubectl run -it --rm health-check --image=busybox -n $NAMESPACE \
  --restart=Never -- wget -qO- http://$APP/health/ready
```

---

## Step 8: Prevent Recurrence

After fixing the drift, make it structurally impossible to repeat:

1. **Update `agent_docs/k8s-layout.md`** — add the env var as a documented dependency for this service
2. **Update `project-graph.json`** — add a relationship edge: `[app-id] → reads-from → [secret-id or configmap-id]`
3. **Trust the pre-deploy hook** — `hooks/pre-deploy.sh` validates all `secretKeyRef` references at deploy time; the hook will catch this class of drift automatically on future deployments
4. **Update `.env.example`** — if the variable is new, add it so the next developer knows it's required

---

## Common Root Causes Reference

| Symptom | Likely Cause |
|---------|--------------|
| CrashLoopBackOff immediately on startup | Required env var missing or empty |
| App starts but DB operations fail | `DATABASE_URL` wrong value (staging/prod mismatch) |
| App starts but auth fails | `SECRET_KEY` or `JWT_SECRET` missing from secret |
| Deployment succeeds but runs old code | `imagePullPolicy: IfNotPresent` with `:latest` tag |
| `secretKeyRef` error in pod events | Secret exists but key was renamed or deleted |
| App sees empty string instead of missing var | Env var present but value is empty string `""` |

---

*Derived from CC-Forge DIAGNOSE mode Phase 3. For full cluster triage including connectivity and resources, run `/diagnose $APP $NAMESPACE`.*
