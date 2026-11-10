locals {
  cluster_issuer_name = var.use_staging_issuer ? "letsencrypt-staging" : "letsencrypt-prod"
  acme_server         = var.use_staging_issuer ? "https://acme-staging-v02.api.letsencrypt.org/directory" : "https://acme-v02.api.letsencrypt.org/directory"

  ingress_service_annotations = var.aws_nlb ? {
    "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
    "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internet-facing"
    "service.beta.kubernetes.io/aws-load-balancer-backend-protocol"                  = "tcp"
    "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
  } : {}

  # k3d/kind ship Traefik on host ports 80/443; LoadBalancer svclb pods cannot bind.
  ingress_service_type = var.aws_nlb ? "LoadBalancer" : "NodePort"
}

# ingress-nginx for non-AWS clusters (on-prem, k3d). Kubernetes SIG Network retired the
# project in March 2026, so it gets no further security fixes: on EKS use the AWS Load
# Balancer Controller (modules/aws-load-balancer-controller) instead.
resource "helm_release" "ingress_nginx" {
  count = var.install_ingress_nginx ? 1 : 0

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = var.ingress_namespace
  create_namespace = true
  version          = var.ingress_nginx_chart_version
  timeout          = 600

  values = [yamlencode({
    controller = {
      ingressClassResource = {
        name            = "nginx"
        default         = true
        controllerValue = "k8s.io/ingress-nginx"
      }
      config = {
        "proxy-body-size"    = "15m"
        "proxy-read-timeout" = "3600"
        "proxy-send-timeout" = "3600"
      }
      service = {
        type        = local.ingress_service_type
        annotations = local.ingress_service_annotations
      }
    }
  })]
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
  })]
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

  set {
    name  = "name"
    value = local.cluster_issuer_name
  }

  set {
    name  = "acmeServer"
    value = local.acme_server
  }

  set {
    name  = "email"
    value = var.letsencrypt_email
  }
}

resource "helm_release" "gp3_storage_class" {
  count = var.install_storage_class ? 1 : 0

  name      = "gp3-storage-class"
  chart     = "${path.module}/charts/gp3-storage-class"
  namespace = "kube-system"
  # StorageClass parameters are immutable: replace the object when they change.
  # Existing volumes keep working; only new volumes use the new class.
  force_update = true

  set {
    name  = "name"
    value = "gp3"
  }
}

resource "time_sleep" "wait_for_ingress" {
  count = var.install_ingress_nginx ? 1 : 0

  depends_on      = [helm_release.ingress_nginx]
  create_duration = "${var.ingress_wait_seconds}s"
}

data "kubernetes_service" "ingress_nginx" {
  count = var.install_ingress_nginx ? 1 : 0

  depends_on = [
    helm_release.ingress_nginx,
    time_sleep.wait_for_ingress,
  ]

  metadata {
    name      = "ingress-nginx-controller"
    namespace = var.ingress_namespace
  }
}

# Keep existing installs in place after adding count.
moved {
  from = helm_release.ingress_nginx
  to   = helm_release.ingress_nginx[0]
}

moved {
  from = helm_release.cert_manager
  to   = helm_release.cert_manager[0]
}

moved {
  from = time_sleep.wait_for_cert_manager_crds
  to   = time_sleep.wait_for_cert_manager_crds[0]
}

moved {
  from = helm_release.cluster_issuer
  to   = helm_release.cluster_issuer[0]
}

moved {
  from = time_sleep.wait_for_ingress
  to   = time_sleep.wait_for_ingress[0]
}
