# Apigene Helm Chart

Deploy the full [Apigene](https://apigene.ai) self-hosted platform on Kubernetes. Same stack as [apigene-docker-compose](https://github.com/apigene/apigene-docker-compose) — UI, API, docs, MCP gateway, MongoDB, and Redis in one install.

## One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/apigene/apigene-helm-chart/main/scripts/install.sh | bash
```

Requires `helm`, `kubectl`, and a configured Kubernetes cluster. Generates an auth secret automatically if `APIGENE_AUTH_SECRET` is unset.

## Prerequisites

- Kubernetes 1.24+
- Helm 3.10+
- A cluster with a default StorageClass (for MongoDB)
- `kubectl` configured for your cluster

## Quick start (manual)

```bash
git clone https://github.com/apigene/apigene-helm-chart.git
cd apigene-helm-chart

# Generate an auth secret (required for production)
export APIGENE_AUTH_SECRET=$(openssl rand -hex 32)

helm install apigene ./chart/apigene \
  --namespace apigene \
  --create-namespace \
  --set auth.secretKey="$APIGENE_AUTH_SECRET"
```

Wait 2–3 minutes for all pods to become ready, then open the LoadBalancer URL:

```bash
kubectl get svc nginx -n apigene
# Or use port-forward:
kubectl port-forward -n apigene svc/nginx 8080:8080
open http://localhost:8080
```

## Testing

Run smoke tests:

```bash
./scripts/smoke.sh
# or with auto port-forward:
./scripts/run-tests.sh --port-forward
```

Run the full integration suite (same coverage as [apigene-docker-compose/tests](https://github.com/apigene/apigene-docker-compose/tree/main/tests), adapted for Kubernetes):

```bash
kubectl port-forward -n apigene svc/nginx 8080:8080 &
BASE_URL=http://localhost:8080 ./tests/integration.sh
```

Or use the combined runner:

```bash
make test
# equivalent to: ./scripts/run-tests.sh --port-forward
```

Local end-to-end (creates k3d cluster, deploys, tests, tears down):

```bash
TEARDOWN=1 ./scripts/test-local-cluster.sh
```

## Configuration

See [`chart/apigene/values.yaml`](chart/apigene/values.yaml) for all options. Common settings:

```yaml
# Pin release (matches docker-compose APIGENE_IMAGE_TAG)
imageTag: "5.2.0"

# Public URL users open in the browser
publicUrl: "https://apigene.example.com"

# Self-hosted auth (default)
auth:
  provider: apigene
  secretKey: ""   # openssl rand -hex 32

# MongoDB PVC
mongo:
  storage: 20Gi

# Expose via LoadBalancer (default) or Ingress
service:
  type: LoadBalancer
  port: 8080

ingress:
  enabled: true
  className: nginx
  host: apigene.example.com
  tls:
    enabled: true
```

Production example:

```bash
helm install apigene ./chart/apigene \
  -f chart/apigene/values-production.yaml \
  --set publicUrl=https://apigene.example.com \
  --set auth.secretKey="$APIGENE_AUTH_SECRET" \
  --set ingress.host=apigene.example.com
```

## Upgrade

```bash
helm upgrade apigene ./chart/apigene \
  --namespace apigene \
  --set imageTag=5.3.0 \
  --reuse-values
```

## Uninstall

```bash
helm uninstall apigene -n apigene
# Mongo data persists in PVC until manually deleted:
kubectl delete pvc -n apigene -l app.kubernetes.io/component=mongo
```

## Routing

| Path | Service |
|------|---------|
| `/` | Copilot UI |
| `/api/*` | Backend API |
| `/docs`, `/redoc` | API documentation |
| `/agent/<name>/mcp` | MCP gateway |

## Connect MCP clients

```
http://<your-host>/agent/<agent-name>/mcp
```

Header: `apigene-api-key: <your-api-key>` (from Settings → API key in the UI)

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Pods stuck in `Pending` | Check StorageClass for Mongo PVC |
| Backend `CrashLoopBackOff` | `kubectl logs -n apigene -l app.kubernetes.io/component=backend` |
| UI loads but API fails | Ensure `publicUrl` matches the URL in your browser |
| `ImagePullBackOff` on Apple Silicon | Images are amd64; use an amd64 node pool |

```bash
kubectl get pods -n apigene
kubectl logs -n apigene -l app.kubernetes.io/component=backend --tail=100
./scripts/smoke.sh
```

## Related

- [Docker Compose install](https://github.com/apigene/apigene-docker-compose)
- [Apigene docs](https://docs.apigene.ai/)
