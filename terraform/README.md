# Apigene Kubernetes — Terraform Deployment

Deploy the full Apigene self-hosted platform on Kubernetes using Terraform. This package provisions AWS infrastructure (optional) and installs the [Apigene Helm chart](../chart/apigene) with production-ready ingress and TLS.

## Examples

| Example | Use case |
|---------|----------|
| [`examples/aws-eks/`](examples/aws-eks/) | Full AWS reference: VPC, EKS, AWS Load Balancer Controller (ALB), ACM, Route53, Apigene |
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
tenant_name    = "acme"                 # subdomain + cluster prefix
aws_region     = "us-east-2"            # AWS region
root_domain    = "example.com"          # your domain
hosted_zone_id = "Z1234567890EXAMPLE"   # from step 2
# image_tag    = "5.26.4"               # empty = release pinned in the chart
```

The TLS certificate comes from ACM, validated through a record in your hosted zone, and renews automatically. No Let's Encrypt setup is needed.

Your platform URL will be: `https://{tenant_name}.{root_domain}` (e.g. `https://acme.example.com`).

### 4. Deploy

```bash
# Initialize Terraform (with remote state)
terraform init -backend-config=backend.conf

# Or without remote state (local state file)
terraform init
```

**Greenfield (new cluster) — two-phase apply**

Kubernetes/Helm providers need a live EKS API. Create the network and cluster first, then install addons and Apigene:

```bash
# Phase 1: VPC + EKS control plane + node group (~10–15 min)
terraform apply -target=module.vpc -target=module.eks -var-file=customer.tfvars

# Confirm the cluster is ACTIVE
aws eks describe-cluster \
  --name "$(terraform output -raw cluster_name)" \
  --region "$(grep aws_region customer.tfvars | awk -F'"' '{print $2}')" \
  --query 'cluster.status'

# Phase 2: addons, DNS, Apigene Helm (~10–15 min)
terraform apply -var-file=customer.tfvars
```

**Day-2 / existing cluster** (cluster already in state):

```bash
terraform plan -var-file=customer.tfvars
terraform apply -var-file=customer.tfvars
```

What gets created:
1. **VPC** — public/private subnets, NAT gateway (one per AZ with `single_nat_gateway = false`), optional flow logs
2. **EKS cluster** — control plane with audit logs, managed node group (~10-15 min)
3. **EKS addons** — vpc-cni (network policy on), coredns, kube-proxy, EBS CSI driver
4. **AWS Load Balancer Controller** — IRSA role with the upstream IAM policy
5. **ACM certificate** — DNS-validated in Route53
6. **Apigene** — Helm release; its Ingress becomes an internet-facing ALB (TLS 1.3 policy, HTTP→HTTPS redirect, 3600s idle timeout for MCP streams)
7. **DNS** — Route53 alias record pointing to the ALB

MongoDB and Redis get generated passwords and MongoDB a nightly `mongodump` CronJob. Read them with `terraform output -raw` on the `apigene` module outputs; keep the state backend encrypted.

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

# Check the ingress (ADDRESS is the ALB DNS name)
kubectl get ingress -n apigene
terraform output alb_dns_name

# Test the API
curl -s https://acme.example.com/api/health
# Should return: {"status":"ok"}
```

### 6. Harden for production

Set these in `customer.tfvars` (see `customer.tfvars.example`):

| Setting | Why |
|---------|-----|
| `cluster_public_access_cidrs` | Only your admin networks can reach the Kubernetes API |
| `alb_inbound_cidrs` / `waf_acl_arn` | Restrict or filter who reaches the ALB |
| `single_nat_gateway = false` | No single point of failure for outbound traffic |
| `enable_vpc_flow_logs = true` | Network audit trail |
| `node_instance_types = ["m6i.large"]` | Non-burstable nodes (replaces the node group) |

Copy the MongoDB backups off the cluster as well: AWS Backup or EBS snapshots of the `mongo-backup` volume.

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
| `image_tag` | Apigene release tag (empty = chart appVersion) | `""` | No |
| `app_replicas` | Replicas for backend, copilot, mcp-gw, nginx | `2` | No |
| `expose_api_docs` | Serve `/docs`, `/redoc`, `/openapi.json` | `false` | No |
| `alb_inbound_cidrs` | CIDRs allowed to reach the ALB | `[]` (internet) | No |
| `waf_acl_arn` | WAFv2 web ACL for the ALB | `""` | No |
| `cluster_public_access_cidrs` | CIDRs allowed to reach the EKS API | `["0.0.0.0/0"]` | No |
| `single_nat_gateway` | One NAT gateway instead of one per AZ | `true` | No |
| `enable_vpc_flow_logs` | VPC flow logs to CloudWatch | `false` | No |
| `auth_secret_key` | Auth secret (auto-generated if empty) | `""` | No |
| `deployment_type` | `SaaS` or `OnPrem` | `SaaS` | No |
| `license_public_key` | OnPrem license verify key (PEM / `base64:…`) | `""` | No |
| `license_algorithm` | License JWT algorithm | `RS256` | No |
| `cluster_name` | Override EKS cluster name | `apigene-{tenant_name}` | No |
| `node_instance_types` | EC2 instance types for nodes | `["t3.large"]` | No |
| `node_desired_size` | Desired worker nodes | `2` | No |
| `node_min_size` | Minimum worker nodes | `2` | No |
| `node_max_size` | Maximum worker nodes | `4` | No |
| `vpc_cidr_block` | VPC CIDR block | `10.0.0.0/16` | No |

Resulting URL: `https://{tenant_name}.{root_domain}`

## What gets created (AWS)

```
terraform/modules/
├── vpc/                          # VPC, 2 public + 2 private subnets, NAT gateway(s), flow logs
├── eks/                          # EKS cluster, managed node group, OIDC, EBS CSI driver, audit logs
├── aws-load-balancer-controller/ # Controller + IRSA role (ALB for the Ingress)
├── acm-certificate/              # ACM certificate, Route53 validation
├── k8s-addons/                   # gp3 StorageClass; ingress-nginx + cert-manager for non-AWS clusters
├── dns/                          # Route53 alias → ALB
└── apigene-helm/                 # Helm release: backend, copilot, mcp-gw, nginx, mongo, redis
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

The gp3 StorageClass uses `reclaimPolicy: Retain`, so MongoDB volumes survive a destroy. Delete the PVCs, then the released EBS volumes, if you no longer need the data:

```bash
kubectl delete pvc -l app.kubernetes.io/component=mongo -n apigene
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `reading EKS Cluster (...): couldn't find resource` | Greenfield run: apply VPC+EKS first with `-target=module.vpc -target=module.eks`, then full apply. Providers use `module.eks` outputs (no cluster data source lookup). |
| `terraform plan` fails with "no client config" | Ensure `depends_on = [module.eks]` is set on `k8s_addons`; complete phase 1 so the cluster exists |
| Helm release `Unauthorized` | EKS token expired during long apply — re-run `terraform apply` |
| `data.aws_lb.apigene`: no matching load balancer | The controller has not created the ALB yet: `kubectl describe ingress nginx -n apigene` and `kubectl logs -n kube-system deploy/aws-load-balancer-controller`, then re-apply |
| ACM validation hangs | The hosted zone is not authoritative for the domain (check the NS delegation) |
| Upgrading from the ingress-nginx version | The apply removes ingress-nginx and cert-manager and moves DNS to the ALB; expect a short switch-over |
| Pods stuck in `Pending` | Check StorageClass: `kubectl get sc` — gp3 should be default |
| `ImagePullBackOff` | Images are amd64 only; ensure nodes are x86 instances |

## Support

- Docs: https://docs.apigene.ai/
- Email: support@apigene.ai
