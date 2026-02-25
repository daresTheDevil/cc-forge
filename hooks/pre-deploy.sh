#!/usr/bin/env bash
# .claude/hooks/pre-deploy.sh
# CC-Forge Pre-Deploy Hook
# Runs before any helm upgrade or kubectl apply.
# Primary job: catch env var drift BEFORE it reaches the running cluster.
# This is the prevention layer for the class of bug that DIAGNOSE mode fixes.
#
# Usage: bash .claude/hooks/pre-deploy.sh [namespace] [manifest-path]
# Called automatically by the /project:build domain gates for k8s changes.

set -euo pipefail

NAMESPACE="${1:-}"
MANIFEST_PATH="${2:-.}"
ERRORS=0
WARNINGS=0

if [ -z "$NAMESPACE" ]; then
  echo "Usage: pre-deploy.sh [namespace] [manifest-path]"
  exit 1
fi

echo "🔍 CC-Forge pre-deploy validation for namespace: $NAMESPACE"
echo ""

# ---------------------------------------------------------------------------
# Gate 1: Validate all secretKeyRef references exist in actual Secrets
# The #1 cause of production env var failures
# ---------------------------------------------------------------------------
echo "  [1/4] Validating secretKeyRef references..."

MANIFESTS=$(find "$MANIFEST_PATH" -name "*.yaml" -o -name "*.yml" 2>/dev/null | head -50)

for manifest in $MANIFESTS; do
  # Extract secretKeyRef entries: secretName and key
  if grep -q "secretKeyRef" "$manifest" 2>/dev/null; then
    # Parse secret name and key pairs from manifest
    python3 - "$manifest" "$NAMESPACE" <<'PYEOF'
import sys, subprocess, json, re

manifest_path = sys.argv[1]
namespace = sys.argv[2]

with open(manifest_path) as f:
    content = f.read()

# Simple regex extraction of secretKeyRef blocks
# Handles: name: secret-name / key: SECRET_KEY pattern
secret_refs = re.findall(
    r'secretKeyRef:\s*\n\s*name:\s*(\S+)\s*\n\s*key:\s*(\S+)',
    content
)

errors = 0
for secret_name, key_name in secret_refs:
    try:
        result = subprocess.run(
            ['microk8s', 'kubectl', 'get', 'secret', secret_name,
             '-n', namespace, '-o', f'jsonpath={{.data.{key_name}}}'],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"    ❌ Secret '{secret_name}' not found in namespace '{namespace}'")
            errors += 1
        elif not result.stdout.strip():
            print(f"    ❌ Key '{key_name}' not found in secret '{secret_name}'")
            print(f"       (secret exists but key is missing — was it renamed or removed?)")
            errors += 1
        else:
            print(f"    ✅ {secret_name}/{key_name}")
    except Exception as e:
        print(f"    ⚠️  Could not validate {secret_name}/{key_name}: {e}")

sys.exit(1 if errors > 0 else 0)
PYEOF
    if [ $? -ne 0 ]; then
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

# ---------------------------------------------------------------------------
# Gate 2: Validate all configMapKeyRef references exist in actual ConfigMaps
# ---------------------------------------------------------------------------
echo "  [2/4] Validating configMapKeyRef references..."

for manifest in $MANIFESTS; do
  if grep -q "configMapKeyRef" "$manifest" 2>/dev/null; then
    python3 - "$manifest" "$NAMESPACE" <<'PYEOF'
import sys, subprocess, re

manifest_path = sys.argv[1]
namespace = sys.argv[2]

with open(manifest_path) as f:
    content = f.read()

cm_refs = re.findall(
    r'configMapKeyRef:\s*\n\s*name:\s*(\S+)\s*\n\s*key:\s*(\S+)',
    content
)

errors = 0
for cm_name, key_name in cm_refs:
    try:
        result = subprocess.run(
            ['microk8s', 'kubectl', 'get', 'configmap', cm_name,
             '-n', namespace, '-o', f'jsonpath={{.data.{key_name}}}'],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            print(f"    ❌ ConfigMap '{cm_name}' not found in namespace '{namespace}'")
            errors += 1
        elif result.stdout.strip() == '':
            print(f"    ❌ Key '{key_name}' not found in ConfigMap '{cm_name}'")
            errors += 1
        else:
            print(f"    ✅ {cm_name}/{key_name}")
    except Exception as e:
        print(f"    ⚠️  Could not validate {cm_name}/{key_name}: {e}")

sys.exit(1 if errors > 0 else 0)
PYEOF
    if [ $? -ne 0 ]; then
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

# ---------------------------------------------------------------------------
# Gate 3: Validate envFrom references (whole ConfigMap/Secret mounts)
# ---------------------------------------------------------------------------
echo "  [3/4] Validating envFrom references..."

for manifest in $MANIFESTS; do
  if grep -q "envFrom" "$manifest" 2>/dev/null; then
    python3 - "$manifest" "$NAMESPACE" <<'PYEOF'
import sys, subprocess, re

manifest_path = sys.argv[1]
namespace = sys.argv[2]

with open(manifest_path) as f:
    content = f.read()

# configMapRef under envFrom
cm_refs = re.findall(r'configMapRef:\s*\n\s*name:\s*(\S+)', content)
secret_refs = re.findall(r'secretRef:\s*\n\s*name:\s*(\S+)', content)

errors = 0
for cm_name in cm_refs:
    result = subprocess.run(
        ['microk8s', 'kubectl', 'get', 'configmap', cm_name, '-n', namespace],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"    ❌ envFrom ConfigMap '{cm_name}' not found in namespace '{namespace}'")
        errors += 1
    else:
        print(f"    ✅ ConfigMap (envFrom): {cm_name}")

for secret_name in secret_refs:
    result = subprocess.run(
        ['microk8s', 'kubectl', 'get', 'secret', secret_name, '-n', namespace],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"    ❌ envFrom Secret '{secret_name}' not found in namespace '{namespace}'")
        errors += 1
    else:
        print(f"    ✅ Secret (envFrom): {secret_name}")

sys.exit(1 if errors > 0 else 0)
PYEOF
    if [ $? -ne 0 ]; then
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

# ---------------------------------------------------------------------------
# Gate 4: Check for image tags that will cause stale deployments
# :latest with IfNotPresent = you deployed but nothing changed
# ---------------------------------------------------------------------------
echo "  [4/4] Checking image tag policy..."

for manifest in $MANIFESTS; do
  if grep -q "image:" "$manifest" 2>/dev/null; then
    # Flag :latest tag
    if grep -qE "image:.*:latest" "$manifest"; then
      echo "    ⚠️  WARNING: :latest image tag detected in $manifest"
      echo "       Use a specific tag or digest. :latest with IfNotPresent = stale deploys."
      WARNINGS=$((WARNINGS + 1))
    fi
    # Flag missing tag (implicit latest)
    if grep -E "image:\s+[^:]+$" "$manifest" | grep -qv "#"; then
      echo "    ⚠️  WARNING: Image with no tag in $manifest (implicit :latest)"
      WARNINGS=$((WARNINGS + 1))
    fi
  fi
done

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
echo ""
if [ $ERRORS -gt 0 ]; then
  echo "❌ CC-Forge pre-deploy: $ERRORS validation failure(s). Deploy BLOCKED."
  echo "   Fix missing secrets/configmap keys before deploying."
  echo "   Run /project:diagnose $NAMESPACE to investigate further."
  exit 1
elif [ $WARNINGS -gt 0 ]; then
  echo "⚠️  CC-Forge pre-deploy: passed with $WARNINGS warning(s). Deploy allowed."
  echo "   Address image tag warnings to prevent stale deployment issues."
  exit 0
else
  echo "✅ CC-Forge pre-deploy: all validations passed. Safe to deploy."
  exit 0
fi
