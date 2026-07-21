provider "aws" {
  region = var.aws_region
}

locals {
  cluster_name = var.cluster_name != "" ? var.cluster_name : "apigene-${var.tenant_name}"
  fqdn         = "${var.tenant_name}.${var.root_domain}"
  chart_path   = abspath("${path.module}/../../../chart/apigene")

  common_tags = merge(var.tags, {
    Project    = "apigene"
    Tenant     = var.tenant_name
    ManagedBy  = "terraform"
    Deployment = "k8s"
  })
}

module "vpc" {
  source = "../../modules/vpc"

  name       = local.cluster_name
  cidr_block = var.vpc_cidr_block
  azs        = []
  tags       = local.common_tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name          = local.cluster_name
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = concat(module.vpc.public_subnet_ids, module.vpc.private_subnet_ids)
  node_subnet_ids       = module.vpc.private_subnet_ids
  node_instance_types   = var.node_instance_types
  node_desired_size     = var.node_desired_size
  enable_ebs_csi_driver = true
  tags                  = local.common_tags
}

data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

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
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

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

module "k8s_addons" {
  source = "../../modules/k8s-addons"

  letsencrypt_email     = var.letsencrypt_email
  use_staging_issuer    = var.use_staging_issuer
  aws_nlb               = true
  install_storage_class = true

  depends_on = [module.eks]
}

module "dns" {
  source = "../../modules/dns"

  hosted_zone_id         = var.hosted_zone_id
  fqdn                   = local.fqdn
  load_balancer_hostname = module.k8s_addons.ingress_hostname

  depends_on = [module.k8s_addons]
}

resource "time_sleep" "wait_for_dns" {
  depends_on      = [module.dns]
  create_duration = "60s"
}

module "apigene" {
  source = "../../modules/apigene-helm"

  chart_path          = local.chart_path
  tenant_name         = var.tenant_name
  fqdn                = local.fqdn
  image_tag           = var.image_tag
  auth_secret_key     = var.auth_secret_key
  cluster_issuer_name = module.k8s_addons.cluster_issuer_name
  storage_class       = "gp3"
  enable_tls          = true

  depends_on = [
    module.k8s_addons,
    module.dns,
    time_sleep.wait_for_dns,
  ]
}
