# AGENTS.md

## Repo role

Deploys the full Apigene self-hosted platform on Kubernetes. Same stack as `apigene-docker-compose` — UI, API, docs, MCP gateway, MongoDB, and Redis.

Does **not** own:
- Application source code → `apigene-backend`, `apigene-copilot`, `apigene-mcp-next`
- Docker Compose local stack → `apigene-docker-compose`

## Sibling repos

| Repo | Relationship |
|------|--------------|
| `apigene-docker-compose` | Compose equivalent; share image tags and routing |
| `apigene-backend` | `backend` deployment |
| `apigene-copilot` | `copilot` deployment |
| `apigene-mcp-next` | `mcp-gw` deployment |

## Start here

| Area | Path |
|------|------|
| Helm chart | `chart/apigene/` |
| Values | `chart/apigene/values.yaml` |
| Terraform modules | `terraform/modules/` |
| Terraform examples | `terraform/examples/aws-eks/`, `terraform/examples/existing-cluster/` |
| Test scripts | `scripts/smoke.sh`, `scripts/run-tests.sh`, `scripts/test-local-cluster.sh` |
| Integration tests | `tests/integration.sh` |
| Makefile | `Makefile` |

## Choose your path

| Goal | Use |
|------|-----|
| Quick K8s install | `helm install` with `chart/apigene/` |
| Local k3d e2e | `TEARDOWN=1 ./scripts/test-local-cluster.sh` |
| AWS EKS + Terraform | `terraform/examples/aws-eks/` |
| Existing cluster + Terraform | `terraform/examples/existing-cluster/` |

## Routing

| Path | Service |
|------|---------|
| `/` | Copilot UI |
| `/api/*` | Backend API |
| `/docs`, `/redoc` | API documentation |
| `/agent/<name>/mcp` | MCP gateway |

## Common change paths

### Change Helm values or templates

1. Edit `chart/apigene/values.yaml` or templates in `chart/apigene/templates/`
2. Run `make test` or `./scripts/smoke.sh`
3. Update `terraform/modules/apigene-helm/` if Terraform wraps the chart

### Pin release version

1. Set `imageTag` in `values.yaml` (currently `5.4.0`)
2. Align with `apigene-docker-compose` `APIGENE_IMAGE_TAG`

### Terraform infrastructure change

1. Edit modules under `terraform/modules/`
2. Test with `scripts/test-terraform-local.sh` or `scripts/test-terraform-aws.sh`
3. Use `*.tfvars.example` and `backend.conf.example` — never commit real values

## Local validation

```bash
# Smoke test (cluster must be running)
./scripts/smoke.sh

# Full test with port-forward
make test

# Local k3d e2e (creates cluster, deploys, tests, tears down)
TEARDOWN=1 ./scripts/test-local-cluster.sh
```

## Env / secrets

- `auth.secretKey` — required for production (`openssl rand -hex 32`)
- `publicUrl` — must match the URL users open in the browser
- `imageTag` — pin for production

## Critical: do not commit

These are in `.gitignore` and must **never** be committed:

- `.terraform/`
- `*.tfstate`, `*.tfstate.*`
- `backend.conf` (use `backend.conf.example`)
- `*.tfvars` except `*.tfvars.example`

If found in the repo, remove and rotate any exposed secrets.

## Cross-repo impact

| Change here | Also update |
|-------------|-------------|
| New service or env var | `apigene-docker-compose` |
| Image tag bump | Both repos' default tags |
| MCP routing | `apigene-mcp-next`, `apigene-docs` |

## Safe defaults for agents

- Use example files (`*.example`) as templates only
- Run smoke/integration tests after chart changes
- Do not commit Terraform state or real tfvars
- Ask before changing production Terraform modules or DNS/ingress config
