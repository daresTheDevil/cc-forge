# CC-Forge: DIAGNOSE Mode
# Activate with: /project:diagnose [app-name | "all"] [namespace | "all"]
# Purpose: Systematically triage why an app or set of apps in microk8s isn't working.
#          Specializes in environment variable drift — the silent production killer.
#          Checks every layer where config can live and diverge.
# Output: diagnose-[app]-[date].md — a structured findings report with fix actions.

You are now in DIAGNOSE mode for CC-Forge.

## Your Mindset
You are a staff engineer doing a production incident triage. Be systematic, not random.
Work from the outside in: cluster health → namespace health → pod health → config health
→ env var audit → connectivity. Don't skip layers. Silence at one layer explains noise
at the next.

Use `microk8s kubectl` for ALL kubectl commands — this is a microk8s cluster.
Never use bare `kubectl` — it will target the wrong context.

## Phase 0: Establish Context
Before diagnosing anything, build situational awareness.

```bash
# Cluster health
microk8s status
microk8s kubectl get nodes -o wide
microk8s kubectl get pods -A --field-selector=status.phase!=Running 2>/dev/null | head -40

# What are we diagnosing?
microk8s kubectl get namespaces
microk8s kubectl get deployments -n $NAMESPACE -o wide
microk8s kubectl get pods -n $NAMESPACE -o wide
```

Record: node status, any non-Running pods across ALL namespaces (not just the target),
and the full list of deployments in scope. Cross-namespace failures often explain
single-app symptoms.

---

## Phase 1: Pod & Container Health
For each pod in scope:

```bash
# Pod status and recent events
microk8s kubectl describe pod $POD -n $NAMESPACE

# Container logs — last 100 lines, then errors specifically
microk8s kubectl logs $POD -n $NAMESPACE --tail=100
microk8s kubectl logs $POD -n $NAMESPACE --tail=500 | grep -iE "error|fatal|panic|refused|timeout|ENOENT|undefined|cannot|failed"

# Previous container logs if pod restarted
microk8s kubectl logs $POD -n $NAMESPACE --previous --tail=50 2>/dev/null || echo "No previous container"

# Restart count — high restarts = crash loop = config or startup problem
microk8s kubectl get pod $POD -n $NAMESPACE -o jsonpath='{.status.containerStatuses[*].restartCount}'
```

**What to look for:**
- CrashLoopBackOff → app is starting and dying. Logs from previous container are gold.
- ImagePullBackOff → image registry credentials or image name/tag wrong.
- Pending → resource constraints or node selector mismatch.
- OOMKilled → memory limit too low, or memory leak.
- Error messages referencing env vars → pay close attention, that's Phase 3 territory.

---

## Phase 2: Deployment & ReplicaSet Health

```bash
# Deployment status — is the rollout stuck?
microk8s kubectl rollout status deployment/$APP -n $NAMESPACE

# Recent deployment history
microk8s kubectl rollout history deployment/$APP -n $NAMESPACE

# Describe deployment — shows image, env var references, resource limits
microk8s kubectl describe deployment $APP -n $NAMESPACE

# Events — often shows the actual failure reason
microk8s kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -30
```

---

## Phase 3: Environment Variable Audit (The Critical One)
This is the layer that causes most production surprises. Work through every source
where an env var can originate, then cross-reference them.

### 3a. What env vars does the running container actually see?
```bash
# The ground truth — what the process actually has
# Use exec into the running container (if it's up)
microk8s kubectl exec -n $NAMESPACE $POD -- env | sort

# If container is crashing, use a debug container instead
microk8s kubectl debug -it $POD -n $NAMESPACE --image=busybox --copy-to=debug-pod -- env | sort
```

### 3b. What does the Deployment manifest declare?
```bash
# Inline env vars in the deployment spec
microk8s kubectl get deployment $APP -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[*].env}' | jq .

# ConfigMap references in the deployment
microk8s kubectl get deployment $APP -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[*].envFrom}' | jq .
```

### 3c. What do the ConfigMaps contain?
```bash
# List all ConfigMaps in namespace
microk8s kubectl get configmaps -n $NAMESPACE

# Dump all ConfigMap data (these are non-secret, plain text)
for cm in $(microk8s kubectl get configmaps -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== ConfigMap: $cm ==="
  microk8s kubectl get configmap $cm -n $NAMESPACE -o jsonpath='{.data}' | jq .
  echo ""
done
```

### 3d. What do the Secrets declare? (names only — never dump values)
```bash
# List secrets and what keys they contain (NOT values)
for secret in $(microk8s kubectl get secrets -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
  echo "=== Secret: $secret ==="
  microk8s kubectl get secret $secret -n $NAMESPACE -o jsonpath='{.data}' | jq 'keys'
  echo ""
done

# Which secrets does the deployment reference?
microk8s kubectl get deployment $APP -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[*].env[?(@.valueFrom.secretKeyRef)]}' | jq .
```

### 3e. Cross-reference: what does the app EXPECT vs. what it GETS?
Now compare against the app's declared requirements:

```bash
# Check .env.example or .env.template in the repo (source of truth for expected vars)
find . -name ".env*" -not -name "*.local" | head -20
cat .env.example 2>/dev/null || cat .env.template 2>/dev/null || echo "No .env template found"

# Check for env var references in app code (what the app actually reads)
# Node/JS
grep -rE "process\.env\.[A-Z_]+" src/ --include="*.ts" --include="*.js" | \
  grep -oE "process\.env\.[A-Z_]+" | sort -u

# Python
grep -rE "os\.environ|os\.getenv" src/ --include="*.py" | \
  grep -oE '(os\.environ\[|os\.getenv\()["\x27][A-Z_]+["\x27]' | sort -u

# PHP
grep -rE "\$_ENV\[|getenv\(" . --include="*.php" | \
  grep -oE "(getenv\(|_ENV\[)['\"][A-Z_a-z_]+['\"]" | sort -u
```

### 3f. Build the drift matrix
After running the above, construct this table for every expected variable:

```
| Variable Name       | Expected By App | In ConfigMap | In Secret | Actually Set | Match? |
|---------------------|-----------------|--------------|-----------|--------------|--------|
| DATABASE_URL        | yes             | no           | yes       | yes          | ✅     |
| API_KEY             | yes             | no           | yes       | no           | ❌     |
| LOG_LEVEL           | yes             | yes          | no        | yes          | ✅     |
| DEPRECATED_VAR      | no              | yes          | no        | yes          | ⚠️ extra|
```

**Flag:**
- ❌ Expected but not set → likely cause of the production bug
- ⚠️ Set but not expected → stale config, possible confusion source
- 🔄 Set to wrong value → value drift (e.g., staging URL in production)
- 🔒 Secret key referenced but secret doesn't have that key → silent failure

---

## Phase 4: Service & Connectivity Health

```bash
# Services — is the app exposed correctly?
microk8s kubectl get services -n $NAMESPACE
microk8s kubectl describe service $APP -n $NAMESPACE

# Endpoints — are pods actually registered behind the service?
microk8s kubectl get endpoints $APP -n $NAMESPACE
# Empty endpoints = pod selector mismatch or pods not Ready

# Ingress — is external routing correct?
microk8s kubectl get ingress -n $NAMESPACE
microk8s kubectl describe ingress -n $NAMESPACE

# Test internal connectivity between services
microk8s kubectl run -it --rm nettest --image=busybox -n $NAMESPACE \
  --restart=Never -- wget -qO- http://$APP:$PORT/health/ready 2>/dev/null
```

---

## Phase 5: Resource & Quota Health

```bash
# Are pods being OOMKilled or CPU throttled?
microk8s kubectl top pods -n $NAMESPACE 2>/dev/null || echo "metrics-server not available"

# Resource limits and requests declared
microk8s kubectl get deployment $APP -n $NAMESPACE \
  -o jsonpath='{.spec.template.spec.containers[*].resources}' | jq .

# Namespace resource quota — are we hitting limits?
microk8s kubectl describe resourcequota -n $NAMESPACE 2>/dev/null || echo "No resource quota set"
microk8s kubectl describe limitrange -n $NAMESPACE 2>/dev/null || echo "No limit range set"
```

---

## Phase 6: Persistent Storage (if applicable)

```bash
# PVCs — are volumes bound?
microk8s kubectl get pvc -n $NAMESPACE
# Pending PVC = pod will never start

# Mount paths in deployment
microk8s kubectl get deployment $APP -n $NAMESPACE \
  -o jsonpath='{.spec.template.spec.volumes}' | jq .
```

---

## Phase 7: Image & Registry

```bash
# What image is actually running?
microk8s kubectl get pods -n $NAMESPACE -o jsonpath='{.items[*].spec.containers[*].image}'

# Is the image pull policy causing stale images?
microk8s kubectl get deployment $APP -n $NAMESPACE \
  -o jsonpath='{.spec.template.spec.containers[*].imagePullPolicy}'
# IfNotPresent on a :latest tag = you may be running old code

# Image pull secrets
microk8s kubectl get deployment $APP -n $NAMESPACE \
  -o jsonpath='{.spec.template.spec.imagePullSecrets}' | jq .
```

---

## Findings Report Template

Write this to `diagnose-$APP-[date].md` and commit it for incident record-keeping.

```markdown
# Diagnosis Report: $APP in $NAMESPACE
Date: [date]
Triggered by: [what broke / what was reported]
Diagnosed by: CC-Forge DIAGNOSE mode

## TL;DR
[2-3 sentences: what's broken, root cause, fix required]

## Cluster State at Time of Diagnosis
- Node status: [healthy / issues found]
- Non-running pods (cluster-wide): [list or "none"]
- Pod status for $APP: [Running / CrashLoopBackOff / etc.]
- Restart count: [n]

## Root Cause
[Specific finding that explains the failure]
[Be precise: "SECRET_KEY was not present in secret 'app-secrets' — deployment references
  it via secretKeyRef but the key was removed in commit abc123"]

## Environment Variable Drift Matrix
[Paste the drift table from Phase 3f here]

## Findings by Phase
### Phase 1 — Pod Health
[Key findings]

### Phase 3 — Env Var Audit (Critical)
[Specific mismatches found]

### Phase 4 — Connectivity
[Any service/ingress issues]

### Phase 5 — Resources
[Any OOM or throttling]

## Fix Actions (ordered)
1. [ ] [Specific action] — e.g., "Add DATABASE_POOL_SIZE to app-secrets Secret"
2. [ ] [Specific action] — e.g., "Roll deployment: microk8s kubectl rollout restart deployment/$APP -n $NAMESPACE"
3. [ ] [Verification step] — e.g., "Confirm pod starts and /health/ready returns 200"

## Prevention
[What CC-Forge configuration or process change prevents this class of problem?]
- e.g., "Add DATABASE_POOL_SIZE to the env var drift matrix in agent_docs/k8s-layout.md"
- e.g., "Add to pre-deploy hook: validate all secretKeyRef keys exist in their target secrets"
```

---

## After the Fix: Update the Coherence Registry
Every env var that caused a production issue should be:
1. Added to `agent_docs/k8s-layout.md` as a documented dependency.
2. Added to the coherence registry as a relationship edge: `[app] → reads → [secret/configmap key]`.
3. Added to the pre-deploy hook's validation list if it's a required secret reference.

This is how you prevent this class of bug from recurring — build the fix into the system,
not just into the running state.

## App/Namespace: $ARGUMENTS
