locals {
  cluster_issuer_name = var.use_staging_issuer ? "letsencrypt-staging" : "letsencrypt-prod"
  acme_server         = var.use_staging_issuer ? "https://acme-staging-v02.api.letsencrypt.org/directory" : "https://acme-v02.api.letsencrypt.org/directory"
}

# Envoy Gateway: the Gateway API implementation for non-AWS clusters (on-prem, k3d). It
# replaces ingress-nginx, which Kubernetes SIG Network retired in March 2026. The chart
# also installs the Gateway API CRDs (v1.6.1). On EKS use the AWS Load Balancer
# Controller (modules/aws-load-balancer-controller) instead.
resource "helm_release" "envoy_gateway" {
  count = var.install_envoy_gateway ? 1 : 0

  name             = "envoy-gateway"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  namespace        = var.envoy_gateway_namespace
  create_namespace = true
  version          = var.envoy_gateway_chart_version
  timeout          = 600
}

# GatewayClass "eg" plus the EnvoyProxy settings for the Service in front of each Gateway.
resource "helm_release" "envoy_gateway_class" {
  count = var.install_envoy_gateway ? 1 : 0

  name      = "envoy-gateway-class"
  chart     = "${path.module}/charts/envoy-gateway-class"
  namespace = var.envoy_gateway_namespace

  values = [yamlencode({
    name               = var.gateway_class_name
    serviceType        = var.gateway_service_type
    serviceAnnotations = var.gateway_service_annotations
  })]

  depends_on = [helm_release.envoy_gateway]
}

resource "helm_release" "cert_manager" {
  count = var.install_cert_manager ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = var.cert_manager_namespace
  create_namespace = true
  version          = var.cert_manager_chart_version
  timeout          = 600

  values = [yamlencode({
    crds = {
      enabled = true
    }
    # Issue certificates for Gateway listeners (cert-manager.io/cluster-issuer on the
    # Gateway) and solve HTTP-01 challenges with an HTTPRoute.
    config = {
      apiVersion = "controller.config.cert-manager.io/v1alpha1"
      kind       = "ControllerConfiguration"
      gatewayAPI = {
        enabled = true
      }
    }
  })]

  # cert-manager watches Gateway API resources only if their CRDs exist at startup.
  depends_on = [helm_release.envoy_gateway]
}

resource "time_sleep" "wait_for_cert_manager_crds" {
  count = var.install_cert_manager ? 1 : 0

  depends_on      = [helm_release.cert_manager]
  create_duration = "90s"
}

resource "helm_release" "cluster_issuer" {
  count = var.install_cert_manager ? 1 : 0

  name       = "cluster-issuer"
  chart      = "${path.module}/charts/cluster-issuer"
  namespace  = var.cert_manager_namespace
  depends_on = [time_sleep.wait_for_cert_manager_crds]

  values = [yamlencode({
    name       = local.cluster_issuer_name
    acmeServer = local.acme_server
    email      = var.letsencrypt_email
    # HTTP-01 challenges are served through the Apigene Gateway's HTTP listener.
    gateway = {
      name      = var.acme_gateway_name
      namespace = var.acme_gateway_namespace
    }
  })]
}

resource "helm_release" "gp3_storage_class" {
  count = var.install_storage_class ? 1 : 0

  name      = "gp3-storage-class"
  chart     = "${path.module}/charts/gp3-storage-class"
  namespace = "kube-system"

  set {
    name  = "name"
    value = "gp3"
  }
}
