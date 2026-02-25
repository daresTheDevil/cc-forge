---
last_verified: YYYY-MM-DD
last_verified_by: [session-id or engineer-name]
drift_check: compare against deploy/helm/templates/**/*.yaml — verify namespaces, deployments, and services match
---

# Kubernetes Layout Reference

> Template — populate during `/discuss` session.
> Replace all `[FILL IN]` sections. Delete this instruction line when done.
> IMPORTANT: All k8s commands use `microk8s kubectl`, never bare `kubectl`.

## Cluster Overview

- **Runtime:** microk8s [FILL IN: version]
- **Node count:** [FILL IN]
- **Storage class:** [FILL IN: default storage class for PVCs]
- **Ingress:** [FILL IN: e.g., ingress-nginx, traefik]
- **Cert manager:** [FILL IN: yes/no, issuer name]

## Namespaces

| Namespace | Purpose | Notes |
|-----------|---------|-------|
| [FILL IN] | | |

## Helm Releases

[FILL IN: For each Helm release:]

### `[release-name]` (namespace: `[ns]`)
- **Chart:** `[chart-name]` v[version]
- **Values file:** `deploy/helm/[release]/values.yaml`
- **Upgrade command:** `helm upgrade [release] [chart] -f values.yaml -n [ns]`
- **Rollback command:** `helm rollback [release] [revision] -n [ns]`
- **Notes:** [anything non-obvious about this release]

## Key Workloads

[FILL IN: For each significant deployment/statefulset:]

### `[deployment-name]`
- **Namespace:** [ns]
- **Replicas:** [n]
- **Image:** [registry/name:tag]
- **Resources:** requests: [cpu/mem], limits: [cpu/mem]
- **Probes:** liveness: [path/port], readiness: [path/port]
- **Secrets:** consumed from [SecretName] via secretKeyRef
- **Notes:** [FILL IN]

## Secrets Management

[FILL IN: How are secrets managed in this cluster?]
- **Pattern:** [e.g., Kubernetes Secrets, sealed-secrets, Vault, external-secrets]
- **Rotation:** [how and when secrets are rotated]
- **NEVER:** plaintext secrets in manifests or values files

## PodSecurityStandard Posture

[FILL IN: What PSS level is enforced?]
- **Policy:** [restricted / baseline / privileged]
- **Exceptions:** [any namespaces running privileged — justify]

## Common Operations

```bash
# Check pod status
microk8s kubectl get pods -n [namespace]

# View logs
microk8s kubectl logs -f deployment/[name] -n [namespace]

# Force rolling restart
microk8s kubectl rollout restart deployment/[name] -n [namespace]

# Check recent events
microk8s kubectl get events -n [namespace] --sort-by='.lastTimestamp' | tail -20
```

## Known Issues / Gotchas

[FILL IN: Things that go wrong, workarounds, known resource contention, etc.]
