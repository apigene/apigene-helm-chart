# Apigene Kubernetes — Terraform Deployment

Deploy the full Apigene self-hosted platform on Kubernetes using Terraform. This package provisions AWS infrastructure (optional) and installs the [Apigene Helm chart](../chart/apigene) with production-ready ingress and TLS.

## Examples

| Example | Use case |
|---------|----------|
| [`examples/aws-eks/`](examples/aws-eks/) | Full AWS reference: VPC, EKS, nginx-ingress, cert-manager, Route53, Apigene |
| [`examples/existing-cluster/`](examples/existing-cluster/) | On-prem / BYO cluster: nginx-ingress + Apigene only |

---

## AWS EKS — Step-by-step guide

### 1. Prerequisites

Before you begin, make sure you have:

- **Terraform** >= 1.5 — [install guide](https://developer.hashicorp.com/terraform/install)
- **AWS CLI** v2 — [install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **kubectl** — [install guide](https://kubernetes.io/docs/tasks/tools/)
- **helm** >= 3.10 — [install guide](https://helm.sh/docs/intro/install/)
- An **AWS account** with permissions to create VPC, EKS, IAM roles, Route53 records
- A **Route53 hosted zone** for your domain (e.g. `example.com`)

Verify your tools:

```bash
terraform version    # >= 1.5
aws sts get-caller-identity   # confirm AWS credentials
kubectl version --client
helm version
```

### 2. Find your Route53 hosted zone ID

```bash
aws route53 list-hosted-zones --query 'HostedZones[*].[Name,Id]' --output table
```

Copy the zone ID (e.g. `Z1234567890EXAMPLE`) for the domain you want to use.

### 3. Configure your deployment

```bash
cd terraform/examples/aws-eks

# (Optional) Set up remote state — recommended for production
cp backend.conf.example backend.conf
# Edit backend.conf:
#   bucket         = "your-terraform-state-bucket"
#   key            = "apigene-k8s/terraform.tfstate"
#   region         = "us-east-2"
#   encrypt        = true

# Create your variables file
cp customer.tfvars.example customer.tfvars
```

Edit `customer.tfvars` with your values:

```hcl
tenant_name       = "acme"                      # subdomain + cluster prefix
aws_region        = "us-east-2"                  # AWS region
root_domain       = "example.com"                # your domain
hosted_zone_id    = "Z1234567890EXAMPLE"         # from step 2
letsencrypt_email = "platform@example.com"       # cert notifications
image_tag         = "5.2.0"                      # Apigene release

use_staging_issuer = true   # start with staging; switch to false after verification
```

Your platform URL will be: `https://{tenant_name}.{root_domain}` (e.g. `https://acme.example.com`).

### 4. Deploy

```bash
# Initialize Terraform (with remote state)
terraform init -backend-config=backend.conf

# Or without remote state (local state file)
terraform init

# Preview what will be created
terraform plan -var-file=customer.tfvars

# Deploy (~20-30 minutes for first run)
terraform apply -var-file=customer.tfvars
```

The apply creates, in order:
1. **VPC** — public/private subnets, NAT gateway
2. **EKS cluster** — control plane + managed node group (~10-15 min)
3. **EKS addons** — vpc-cni, coredns, kube-proxy, EBS CSI driver
4. **Kubernetes addons** — nginx-ingress (NLB), cert-manager, ClusterIssuer, gp3 StorageClass
5. **DNS** — Route53 A record pointing to the NLB
6. **Apigene** — Helm release with all services (backend, copilot, mcp-gw, nginx, mongo, redis)

### 5. Verify the deployment

```bash
# Configure kubectl
aws eks update-kubeconfig \
  --name $(terraform output -raw cluster_name) \
  --region $(grep aws_region customer.tfvars | awk -F'"' '{print $2}')

# Check all pods are Running
kubectl get pods -n apigene

# Expected output — all pods should show 1/1 Running:
#   backend-xxx          1/1   Running
#   backend-worker-xxx   1/1   Running
#   copilot-xxx          1/1   Running
#   mcp-gw-xxx           1/1   Running
#   mongo-0              1/1   Running
#   nginx-xxx            1/1   Running
#   redis-xxx            1/1   Running

# Check ingress and certificate
kubectl get ingress,certificate -n apigene

# Test the API
curl -sk https://acme.example.com/api/health
# Should return: {"status":"ok"}
```

### 6. Switch to production TLS certificate

The initial deploy uses Let's Encrypt **staging** (browsers show a certificate warning). Once everything is working:

1. Edit `customer.tfvars`:

```hcl
use_staging_issuer = false
```

2. Re-apply:

```bash
terraform apply -var-file=customer.tfvars
```

3. Force certificate renewal (the old staging cert is cached):

```bash
kubectl delete certificate -n apigene --all
kubectl delete secret -n apigene apigene-tls 2>/dev/null || true
```

4. Wait for the new production certificate (~1-3 minutes):

```bash
kubectl get certificate -n apigene -w
# Wait until READY shows True
```

5. Open `https://acme.example.com` — the browser warning should be gone.

### 7. Sign up and start using

Open your platform URL in the browser and create your first account. The signup flow creates an admin user and provisions the organization.

---

## Existing cluster (on-prem / BYO)

For clusters that already exist (on-prem, GKE, AKS, k3d, etc.):

```bash
cd terraform/examples/existing-cluster

cp customer.tfvars.example customer.tfvars
# Edit customer.tfvars: tenant_name, fqdn, etc.

terraform init
terraform apply -var-file=customer.tfvars

# For local access:
kubectl port-forward -n apigene svc/nginx 8080:8080
open http://localhost:8080
```

---

## Variables reference (AWS EKS)

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `tenant_name` | Tenant prefix + DNS subdomain | — | Yes |
| `aws_region` | AWS region | `eu-central-1` | Yes |
| `root_domain` | Root DNS zone | `apigene.ai` | Yes |
| `hosted_zone_id` | Route53 zone ID | — | Yes |
| `letsencrypt_email` | Let's Encrypt registration email | — | Yes |
| `image_tag` | Apigene release tag | `5.2.0` | No |
| `use_staging_issuer` | Use LE staging (for testing) | `false` | No |
| `auth_secret_key` | Auth secret (auto-generated if empty) | `""` | No |
| `cluster_name` | Override EKS cluster name | `apigene-{tenant_name}` | No |
| `node_instance_types` | EC2 instance types for nodes | `["t3.large"]` | No |
| `node_desired_size` | Number of worker nodes | `2` | No |
| `vpc_cidr_block` | VPC CIDR block | `10.0.0.0/16` | No |

Resulting URL: `https://{tenant_name}.{root_domain}`

## What gets created (AWS)

```
terraform/modules/
├── vpc/           # VPC, 2 public + 2 private subnets, NAT gateway
├── eks/           # EKS cluster, managed node group, OIDC, EBS CSI driver
├── k8s-addons/    # nginx-ingress (NLB), cert-manager, ClusterIssuer, gp3 StorageClass
├── dns/           # Route53 A record → NLB
└── apigene-helm/  # Helm release: backend, copilot, mcp-gw, nginx, mongo, redis
```

## Testing

```bash
# Static validation (CI)
make terraform-validate

# Post-apply AWS verification
./scripts/test-terraform-aws.sh
```

## Destroy

```bash
terraform destroy -var-file=customer.tfvars
```

MongoDB PVCs persist after destroy. Delete manually if needed:

```bash
kubectl delete pvc -l app.kubernetes.io/component=mongo -n apigene
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `terraform plan` fails with "no client config" | Ensure `depends_on = [module.eks]` is set on `k8s_addons` |
| Helm release `Unauthorized` | EKS token expired during long apply — re-run `terraform apply` |
| Cert warning in browser | Still using staging issuer — set `use_staging_issuer = false` and re-apply |
| Signup returns "Failed to create account" | Staging cert issue — copilot can't verify TLS to itself; switch to production issuer |
| Pods stuck in `Pending` | Check StorageClass: `kubectl get sc` — gp3 should be default |
| `ImagePullBackOff` | Images are amd64 only; ensure nodes are x86 instances |

## Support

- Docs: https://docs.apigene.ai/
- Email: support@apigene.ai
