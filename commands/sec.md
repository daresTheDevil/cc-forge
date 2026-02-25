---
description: Full security audit of the project. Scans code, dependencies, secrets, and infrastructure. Updates .forge/security.json scorecard with findings. HALT findings stop all other work.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# CC-Forge: SEC — Security Audit

You are running a systematic security audit. Cover all four domains: code, dependencies, secrets, and infrastructure.

`[HALT]` findings must be surfaced immediately — they block all other work. No exceptions.

---

## Pre-Audit

1. Read `.forge/security.json` to understand the current scorecard baseline.
2. Note when the last audit ran (`last_audit` field).
3. Check git log for changes since last audit.

---

## Domain 1: Code Security Audit

### SQL Injection
```bash
# Find string concatenation in SQL queries
grep -rE "(\"SELECT|'SELECT|\"INSERT|'INSERT|\"UPDATE|'UPDATE|\"DELETE|'DELETE).*\+" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.php" .

# Find f-strings or string interpolation in SQL (Python)
grep -rE "f\".*SELECT|f'.*SELECT|%.*SELECT|format.*SELECT" --include="*.py" .

# Find PHP SQL concat
grep -rE "\\\$.*SELECT|mysql_query.*\\\$|mysqli_query.*\\\$" --include="*.php" .
```

### Command Injection
```bash
# exec/spawn with user-controlled input
grep -rE "(exec|spawn|execSync|spawnSync|system|passthru|shell_exec)\s*\(" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.php" . | head -20
```

### Hardcoded Credentials
```bash
# Common credential patterns
grep -rE "(password|passwd|pwd|secret|api_key|apikey|token|credential|auth)\s*[=:]\s*[\"'][^\"']{4,}[\"']" \
  --include="*.ts" --include="*.js" --include="*.py" --include="*.php" \
  --include="*.yaml" --include="*.yml" --include="*.json" \
  --exclude-dir=node_modules --exclude-dir=vendor \
  . | grep -v "process.env\|os.environ\|getenv\|env\.\|placeholder\|example\|test\|mock" | head -20

# Private key material
grep -rn "BEGIN.*PRIVATE KEY\|BEGIN RSA\|BEGIN EC PRIVATE" \
  --exclude-dir=node_modules --exclude-dir=vendor . | head -10
```

### Input Validation
```bash
# API routes without explicit validation (look for routes that directly use req.body/params)
grep -rE "req\.(body|params|query)\.[a-zA-Z]+" --include="*.ts" --include="*.js" . \
  | grep -v "validate\|schema\|zod\|joi\|check" | head -20
```

---

## Domain 2: Dependency Audit

```bash
# npm/bun vulnerability scan
npm audit --json 2>/dev/null | jq '{
  critical: .metadata.vulnerabilities.critical,
  high: .metadata.vulnerabilities.high,
  moderate: .metadata.vulnerabilities.moderate
}' 2>/dev/null || bun audit 2>/dev/null | tail -10

# Outdated major versions (semver major bumps = potential breaking security changes)
npm outdated --json 2>/dev/null | jq 'to_entries | map(select(.value.current | split(".")[0] != (.value.wanted | split(".")[0]))) | length' 2>/dev/null || echo "0"

# PHP
composer audit --no-ansi 2>/dev/null | tail -20

# Python
pip3 list --format=json 2>/dev/null | python3 -c "import sys,json; pkgs=json.load(sys.stdin); print(len(pkgs), 'packages')" 2>/dev/null || true
pip3 audit 2>/dev/null | tail -10 || true

# SAST (if available)
command -v semgrep >/dev/null 2>&1 && semgrep --config=auto --json . 2>/dev/null | jq '.results | length' 2>/dev/null || true
command -v bandit >/dev/null 2>&1 && bandit -r . -f json 2>/dev/null | jq '.results | length' 2>/dev/null || true
```

---

## Domain 3: Secrets Audit

```bash
# Git-secrets scan (scans entire git history)
command -v git-secrets >/dev/null 2>&1 && git secrets --scan-history 2>&1 | tail -20 || true

# Trufflehog (verified secrets in history)
command -v trufflehog >/dev/null 2>&1 && trufflehog git file://. --since-commit HEAD~20 --only-verified --fail 2>&1 | tail -20 || true

# Check if .env files are committed
git ls-files | grep -E "^\.env$|^\.env\." && echo "[HALT][SEC] .env file(s) tracked in git" || echo "No .env files in git"

# AWS key patterns in code
grep -rn "AKIA[0-9A-Z]{16}" --exclude-dir=node_modules --exclude-dir=vendor . 2>/dev/null | head -5 || true
```

---

## Domain 4: Infrastructure Security (k8s)

```bash
# Pods without resource limits
microk8s kubectl get pods --all-namespaces -o json 2>/dev/null | \
  jq '[.items[] | select(.spec.containers[].resources.limits == null)] | length' 2>/dev/null || echo "0"

# Pods without security context
microk8s kubectl get pods --all-namespaces -o json 2>/dev/null | \
  jq '[.items[] | select(.spec.securityContext == null or .spec.containers[].securityContext == null)] | length' 2>/dev/null || echo "0"

# Secrets in plaintext in manifests (critical)
grep -rn "stringData:\|value:.*password\|value:.*secret\|value:.*key" deploy/ k8s/ 2>/dev/null | \
  grep -v "secretKeyRef\|env\|configMapKeyRef" | head -10 || true

# Network policies
microk8s kubectl get networkpolicies --all-namespaces 2>/dev/null | wc -l || echo "0"
```

---

## Scoring

Grade each domain 0–100. Score calculation:
- Start at 100
- Critical finding: −30
- High finding: −15
- Medium finding: −5
- Low finding: −1

Overall score = average of the four domain scores.

**Score thresholds:**
- 90–100: 🟢 Healthy
- 70–89: 🟡 Needs attention
- 50–69: 🟠 Significant risk
- 0–49: 🔴 Critical — stop other work

---

## Update .forge/security.json

Write the updated scorecard:

```json
{
  "scores": {
    "code": [0-100],
    "deps": [0-100],
    "secrets": [0-100],
    "infra": [0-100],
    "overall": [average]
  },
  "last_audit": "[ISO timestamp]",
  "findings": {
    "code": { "critical": N, "high": N, "medium": N, "low": N },
    "deps": { "critical_vulns": N, "high_vulns": N, "outdated_major": N },
    "secrets": { "rotation_schedule": {} },
    "infra": {
      "pods_without_resource_limits": N,
      "pods_without_security_context": N,
      "network_policies_missing": true/false,
      "rbac_violations": N
    }
  }
}
```

---

## Output

Print a security report to the terminal:

```
CC-Forge Security Audit — [Date]
==================================
Code:     [score]/100  ([critical] critical, [high] high)
Deps:     [score]/100  ([count] vulns)
Secrets:  [score]/100  ([count] issues)
Infra:    [score]/100  ([count] issues)
Overall:  [score]/100

[HALT] Findings (fix before any other work):
[list or "None"]

[REVIEW] Findings:
[list or "None"]

Scorecard written to .forge/security.json
```

## Scope: $ARGUMENTS
