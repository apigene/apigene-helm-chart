locals {
  chart_path = abspath("${path.module}/../../../chart/apigene")
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
  }
}

module "k8s_addons" {
  count  = var.install_addons ? 1 : 0
  source = "../../modules/k8s-addons"

  letsencrypt_email     = var.letsencrypt_email
  use_staging_issuer    = var.use_staging_issuer
  gateway_service_type  = var.gateway_service_type
  install_storage_class = var.install_storage_class
}

locals {
  cluster_issuer_name = var.install_addons ? module.k8s_addons[0].cluster_issuer_name : var.cluster_issuer_name
  gateway_class_name  = var.install_addons ? module.k8s_addons[0].gateway_class_name : var.gateway_class_name
}

module "apigene" {
  source = "../../modules/apigene-helm"

  chart_path                             = local.chart_path
  tenant_name                            = var.tenant_name
  fqdn                                   = var.fqdn
  image_tag                              = var.image_tag
  auth_secret_key                        = var.auth_secret_key
  cluster_issuer_name                    = local.cluster_issuer_name
  gateway_class_name                     = local.gateway_class_name
  enable_tls                             = var.enable_tls
  public_url_port                        = var.public_url_port
  copilot_internal_public_url_host_alias = var.copilot_internal_public_url_host_alias

  depends_on = [module.k8s_addons]
}
