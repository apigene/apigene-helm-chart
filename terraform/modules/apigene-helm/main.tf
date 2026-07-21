resource "random_password" "auth_secret" {
  count = var.auth_secret_key == "" ? 1 : 0

  length  = 64
  special = false
}

locals {
  auth_secret_key = var.auth_secret_key != "" ? var.auth_secret_key : random_password.auth_secret[0].result
  public_url_base = var.enable_tls ? "https://${var.fqdn}" : "http://${var.fqdn}"
  public_url      = var.public_url_port > 0 ? "${local.public_url_base}:${var.public_url_port}" : local.public_url_base

  ingress_annotations = merge(
    var.enable_tls ? {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer_name
    } : {},
    {
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "15m"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "3600"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "3600"
    }
  )

  base_values = {
    imageTag   = var.image_tag
    tenantName = var.tenant_name
    publicUrl  = local.public_url
    auth = {
      secretKey = local.auth_secret_key
    }
    service = {
      type = "ClusterIP"
    }
    ingress = {
      enabled     = true
      host        = var.fqdn
      className   = "nginx"
      annotations = local.ingress_annotations
      tls = {
        enabled = var.enable_tls
      }
    }
    mongo = merge(
      { storage = var.mongo_storage },
      var.storage_class != "" ? { storageClass = var.storage_class } : {}
    )
    deploymentType = var.deployment_type
    databaseEnv    = var.database_env
    copilot = {
      internalPublicUrlHostAlias = var.copilot_internal_public_url_host_alias
    }
  }

  helm_values = merge(local.base_values, var.extra_values)
}

resource "helm_release" "apigene" {
  name             = var.release_name
  chart            = var.chart_path
  namespace        = var.namespace
  create_namespace = true
  wait             = var.wait
  timeout          = var.timeout

  values = [yamlencode(local.helm_values)]
}
