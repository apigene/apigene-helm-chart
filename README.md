# Apigene Helm Chart

Deploy the full [Apigene](https://apigene.ai) self-hosted platform on Kubernetes. Same stack as [apigene-docker-compose](https://github.com/apigene/apigene-docker-compose) — UI, API, docs, MCP gateway, MongoDB, and Redis in one install.

## One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/apigene/apigene-helm-chart/main/scripts/install.sh | bash
```

Requires `git`, `helm`, `kubectl`, and a **reachable** Kubernetes cluster (`kubectl cluster-info` must succeed). Clones to `~/apigene-helm` and runs `helm upgrade --install`.

If you see `cluster unreachable`, your kubectl context may be stale (e.g. after `k3d cluster delete`):

```bash
k3d cluster create apigene --agents 1 --wait
curl -fsSL https://raw.githubusercontent.com/apigene/apigene-helm-chart/main/scripts/install.sh | bash
```

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

Wait 2–3 minutes for all pods to become ready, then port-forward (the default Service is `ClusterIP`; expose it through an ingress for real users):

```bash
helm test apigene -n apigene
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
# Pin release (empty = the chart appVersion)
imageTag: ""

# Public URL users open in the browser
publicUrl: "https://apigene.example.com"

# Self-hosted auth (default)
auth:
  provider: apigene
  secretKey: ""   # openssl rand -hex 32

# Optional OnPrem licensing (default SaaS). Trial works without publicKey.
# deploymentType: OnPrem
# license:
#   publicKey: "base64:…"   # required only to accept pasted licenses
#   algorithm: RS256

# MongoDB PVC
mongo:
  storage: 20Gi

# ClusterIP (default) behind an Ingress; LoadBalancer serves plain HTTP
service:
  type: ClusterIP
  port: 8080

ingress:
  enabled: true
  className: nginx
  host: apigene.example.com
  tls:
    enabled: true
```

Production example (Helm only). `values-production.yaml` turns on MongoDB and Redis passwords, nightly MongoDB backups, two replicas per stateless service and hides the API docs:

```bash
helm install apigene ./chart/apigene -n apigene --create-namespace \
  -f chart/apigene/values-production.yaml \
  --set publicUrl=https://apigene.example.com \
  --set ingress.host=apigene.example.com \
  --set auth.secretKey="$APIGENE_AUTH_SECRET" \
  --set mongo.auth.password="$APIGENE_MONGO_PASSWORD" \
  --set redis.auth.password="$APIGENE_REDIS_PASSWORD"
```

Prefer keeping secrets out of Helm values: create a Secret (for example synced from AWS Secrets Manager by [External Secrets Operator](https://external-secrets.io/)) and set `auth.existingSecret`. See the key list in `values.yaml`.

### Amazon EKS (ALB)

On EKS, put an Application Load Balancer from the [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/) in front of the chart instead of ingress-nginx. ingress-nginx was retired by Kubernetes SIG Network in March 2026 and gets no more security fixes.

```bash
helm install apigene ./chart/apigene -n apigene --create-namespace \
  -f chart/apigene/values-production.yaml \
  -f chart/apigene/values-aws.yaml \
  --set publicUrl=https://apigene.example.com \
  --set ingress.host=apigene.example.com \
  --set ingress.alb.certificateArn="$ACM_CERT_ARN" \
  --set auth.existingSecret=apigene-env
```

```
Route53 → ALB (ACM TLS, WAF, idle timeout 3600s) → nginx pods (IP targets) → copilot / backend / mcp-gw
```

The in-cluster `nginx` stays as the application router (path routing, MCP streaming, Keycloak sign-up block). The ALB replaces only the ingress controller and cert-manager. `ingress.alb` covers the certificate, scheme, WAF, inbound CIDRs, IngressGroup and load balancer attributes.

**Why not API Gateway in front?** API Gateway integrations time out after 29 seconds (15 minutes with REST API response streaming). MCP sessions stay open for up to an hour, so API Gateway would cut them. Use AWS WAF on the ALB for rate limiting and filtering.

### Security defaults

- Pods run as non-root with `seccompProfile: RuntimeDefault`, no privilege escalation and all capabilities dropped (Pod Security Standards `restricted`). nginx, MongoDB, Redis and the init containers use a read-only root filesystem. Override per component with `<component>.podSecurityContext` and `<component>.securityContext`.
- A dedicated ServiceAccount without a mounted API token. Add IRSA with `serviceAccount.annotations`, or associate an EKS Pod Identity role with it.
- `networkPolicy.enabled` limits inbound traffic to the namespace plus the ingress path. On EKS, enable network policy in the VPC CNI add-on.
- Changing the secret or the nginx config restarts the affected pods (checksum annotations).

For AWS EKS or on-prem cluster deployment via Terraform, see [`terraform/README.md`](terraform/README.md):

```bash
cd terraform/examples/aws-eks
terraform init -backend-config=backend.conf
cp customer.tfvars.example customer.tfvars
terraform apply -var-file=customer.tfvars
```

## Private registry

When the cluster cannot reach public registries, publish the images to your own registry and set `images.mirror`. Every image then comes from there, including MongoDB, Redis and the init image.

On a machine with access to your registry, using `apigene-docker-compose`:

```bash
./olgene images load
./olgene images push registry.example.com/apigene
```

Then install with the same registry and tag:

```bash
helm install apigene ./chart/apigene -n apigene --create-namespace \
  --set images.mirror=registry.example.com/apigene \
  --set imageTag=5.25.7 \
  --set auth.secretKey="$APIGENE_AUTH_SECRET"
```

Add `images.pullSecrets` when the registry requires a login.

## Upgrade

Keep your settings in a values file and pass it on every upgrade. `--reuse-values` skips new chart defaults.

```bash
helm upgrade apigene ./chart/apigene -n apigene -f my-values.yaml --set imageTag=5.26.4
```

### Upgrading from chart 0.1.x

- **MongoDB StatefulSet.** The PVC template labels no longer carry versions, and Kubernetes does not allow editing them in place. Before the first upgrade, delete the StatefulSet object only; the pod and its volume stay:

  ```bash
  kubectl delete statefulset mongo -n apigene --cascade=orphan
  helm upgrade apigene ./chart/apigene -n apigene -f my-values.yaml
  ```

- **Namespace.** Resources now go to the release namespace (`helm -n`). `namespace.name` still overrides it.
- **Service type.** The default is `ClusterIP`. Set `service.type=LoadBalancer` to keep the old behaviour.
- **Non-root pods.** Every container now runs as a non-root user. MongoDB's existing files get group access through `fsGroup` on the next start.
- **Images.** The default tag is the chart `appVersion` instead of `latest`. MongoDB, Redis and busybox come from ECR Public (`public.ecr.aws/docker/library`) to avoid Docker Hub rate limits.

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
| `container has runAsNonRoot and image will run as root` | A custom image without a numeric user; set `<component>.podSecurityContext.runAsUser` |
| `/docs` returns 404 | `nginx.exposeApiDocs` is off (the production default) |
| MCP stream drops after 60s behind an ALB | Set `ingress.alb.idleTimeoutSeconds` (default 3600) |

```bash
kubectl get pods -n apigene
kubectl logs -n apigene -l app.kubernetes.io/component=backend --tail=100
./scripts/smoke.sh
```

## Related

- [Docker Compose install](https://github.com/apigene/apigene-docker-compose)
- [Apigene docs](https://docs.apigene.ai/)
