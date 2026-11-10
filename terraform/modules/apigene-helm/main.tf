resource "random_password" "auth_secret" {
  count = var.auth_secret_key == "" ? 1 : 0

  length  = 64
  special = false
}

# Passwords for the bundled MongoDB and Redis. They live in Terraform state: keep the
# state backend encrypted and access-controlled.
resource "random_password" "mongo" {
  count = var.mongo_auth ? 1 : 0

  length  = 40
  special = false
}

resource "random_password" "redis" {
  count = var.redis_auth ? 1 : 0

  length  = 40
  special = false
}

locals {
  auth_secret_key = var.auth_secret_key != "" ? var.auth_secret_key : random_password.auth_secret[0].result
  public_url_base = var.enable_tls ? "https://${var.fqdn}" : "http://${var.fqdn}"
  public_url      = var.public_url_port > 0 ? "${local.public_url_base}:${var.public_url_port}" : local.public_url_base

  # cert-manager issues the HTTPS listener certificate everywhere except on AWS, where
  # the ALB uses ACM.
  gateway_annotations = !var.aws_load_balancer && var.enable_tls && var.cluster_issuer_name != "" ? {
    "cert-manager.io/cluster-issuer" = var.cluster_issuer_name
  } : {}

  stateless_replicas = {
    replicas = var.app_replicas
  }

  base_values = merge(
    var.image_tag != "" ? { imageTag = var.image_tag } : {},
    {
      tenantName = var.tenant_name
      publicUrl  = local.public_url
      service = {
        type = "ClusterIP"
      }
      gateway = {
        enabled     = true
        host        = var.fqdn
        className   = var.gateway_class_name
        annotations = local.gateway_annotations
        tls = {
          enabled = var.enable_tls
        }
        aws = {
          enabled          = var.aws_load_balancer
          certificateArn   = var.certificate_arn
          loadBalancerName = var.load_balancer_name
          sourceRanges     = var.alb_inbound_cidrs
          wafv2AclArn      = var.waf_acl_arn
          tags             = var.alb_tags
        }
      }
      mongo = merge(
        {
          storage = var.mongo_storage
          auth    = { enabled = var.mongo_auth }
          backup  = { enabled = var.mongo_backup }
        },
        var.storage_class != "" ? { storageClass = var.storage_class } : {}
      )
      redis = {
        auth = { enabled = var.redis_auth }
      }
      backend = local.stateless_replicas
      copilot = merge(local.stateless_replicas, {
        internalPublicUrlHostAlias = var.copilot_internal_public_url_host_alias
      })
      mcpGw = local.stateless_replicas
      nginx = merge(local.stateless_replicas, {
        exposeApiDocs = var.expose_api_docs
      })
      networkPolicy = {
        enabled                = length(var.network_policy_ingress_cidrs) > 0 || length(var.network_policy_ingress_namespace_labels) > 0
        ingressCidrs           = var.network_policy_ingress_cidrs
        ingressNamespaceLabels = var.network_policy_ingress_namespace_labels
      }
      serviceAccount = {
        annotations = var.service_account_annotations
      }
      deploymentType = var.deployment_type
      databaseEnv    = var.database_env
      license = {
        algorithm = var.license_algorithm
      }
    }
  )

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

  # Secrets go through set_sensitive so they stay out of plan output.
  set_sensitive {
    name  = "auth.secretKey"
    value = local.auth_secret_key
  }

  dynamic "set_sensitive" {
    for_each = var.mongo_auth ? [random_password.mongo[0].result] : []
    content {
      name  = "mongo.auth.password"
      value = set_sensitive.value
    }
  }

  dynamic "set_sensitive" {
    for_each = var.redis_auth ? [random_password.redis[0].result] : []
    content {
      name  = "redis.auth.password"
      value = set_sensitive.value
    }
  }

  dynamic "set_sensitive" {
    for_each = var.license_public_key != "" ? [var.license_public_key] : []
    content {
      name  = "license.publicKey"
      value = set_sensitive.value
    }
  }
}
