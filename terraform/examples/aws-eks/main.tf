provider "aws" {
  region = var.aws_region
}

locals {
  cluster_name = var.cluster_name != "" ? var.cluster_name : "apigene-${var.tenant_name}"
  fqdn         = "${var.tenant_name}.${var.root_domain}"
  # Fixed ALB name (max 32 characters) so the DNS record can look the ALB up.
  load_balancer_name = substr("apigene-${var.tenant_name}", 0, 32)
  chart_path         = abspath("${path.module}/../../../chart/apigene")

  common_tags = merge(var.tags, {
    Project    = "apigene"
    Tenant     = var.tenant_name
    ManagedBy  = "terraform"
    Deployment = "k8s"
  })
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.cluster_name
  cidr_block         = var.vpc_cidr_block
  azs                = []
  single_nat_gateway = var.single_nat_gateway
  enable_flow_logs   = var.enable_vpc_flow_logs
  tags               = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name          = local.cluster_name
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  node_subnet_ids       = module.vpc.private_subnet_ids
  node_instance_types   = var.node_instance_types
  node_desired_size     = var.node_desired_size
  node_min_size         = var.node_min_size
  node_max_size         = var.node_max_size
  enable_ebs_csi_driver = true
  public_access_cidrs   = var.cluster_public_access_cidrs
  tags                  = local.common_tags
}

# Use module outputs (not a data source) so greenfield applies do not require
# the cluster to already exist. First apply should still create VPC+EKS first
# (see terraform/README.md) before kubernetes/helm providers can talk to the API.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region,
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        var.aws_region,
      ]
    }
  }
}

# gp3 StorageClass only: TLS and load balancing come from ACM + the AWS Load Balancer
# Controller (Gateway API), so Envoy Gateway and cert-manager are not installed.
module "k8s_addons" {
  source = "../../modules/k8s-addons"

  install_envoy_gateway = false
  install_cert_manager  = false
  install_storage_class = true

  depends_on = [module.eks]
}

module "aws_load_balancer_controller" {
  source = "../../modules/aws-load-balancer-controller"

  cluster_name      = module.eks.cluster_name
  region            = var.aws_region
  vpc_id            = module.vpc.vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  tags              = local.common_tags

  depends_on = [module.eks]
}

module "certificate" {
  source = "../../modules/acm-certificate"

  fqdn           = local.fqdn
  hosted_zone_id = var.hosted_zone_id
  tags           = local.common_tags
}

module "apigene" {
  source = "../../modules/apigene-helm"

  chart_path      = local.chart_path
  tenant_name     = var.tenant_name
  fqdn            = local.fqdn
  image_tag       = var.image_tag
  auth_secret_key = var.auth_secret_key
  storage_class   = "gp3"
  enable_tls      = true

  gateway_class_name = module.aws_load_balancer_controller.gateway_class_name
  aws_load_balancer  = true
  certificate_arn    = module.certificate.certificate_arn
  load_balancer_name = local.load_balancer_name
  alb_inbound_cidrs  = var.alb_inbound_cidrs
  waf_acl_arn        = var.waf_acl_arn
  alb_tags           = local.common_tags

  app_replicas    = var.app_replicas
  expose_api_docs = var.expose_api_docs

  # ALB IP targets: traffic to nginx comes from the ALB inside the VPC.
  network_policy_ingress_cidrs = [var.vpc_cidr_block]

  # The controller must outlive the Gateway so it can delete the ALB on destroy.
  depends_on = [
    module.k8s_addons,
    module.aws_load_balancer_controller,
  ]
}

# The controller creates the ALB asynchronously after the Gateway appears.
resource "time_sleep" "wait_for_alb" {
  depends_on      = [module.apigene]
  create_duration = "120s"
}

data "aws_lb" "apigene" {
  name = local.load_balancer_name

  depends_on = [time_sleep.wait_for_alb]
}

module "dns" {
  source = "../../modules/dns"

  hosted_zone_id         = var.hosted_zone_id
  fqdn                   = local.fqdn
  load_balancer_dns_name = data.aws_lb.apigene.dns_name
  load_balancer_zone_id  = data.aws_lb.apigene.zone_id
}
