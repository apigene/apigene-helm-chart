# AWS Load Balancer Controller: turns the Apigene Gateway (GatewayClass "alb") into an
# Application Load Balancer. IAM through IRSA, scoped to the controller's service account.
#
# iam_policy.json is the upstream policy for the pinned controller version:
# https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.6.2/docs/install/iam_policy.json
# Refresh it whenever chart_version changes.
#
# Gateway API: the controller turns on its Gateway support only when the Gateway API
# CRDs exist at startup, so they are installed first (charts/gateway-api-crds, vendored
# by scripts/update-gateway-api-crds.sh). Its own Gateway CRDs (LoadBalancerConfiguration,
# TargetGroupConfiguration, ListenerRuleConfiguration) ship in the controller chart.

locals {
  oidc_issuer          = replace(var.oidc_issuer_url, "https://", "")
  service_account_name = "aws-load-balancer-controller"
}

resource "aws_iam_policy" "this" {
  name        = "${var.cluster_name}-aws-load-balancer-controller"
  description = "AWS Load Balancer Controller for EKS cluster ${var.cluster_name}"
  policy      = file("${path.module}/iam_policy.json")
  tags        = var.tags
}

resource "aws_iam_role" "this" {
  name = "${var.cluster_name}-aws-load-balancer-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.oidc_provider_arn }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace}:${local.service_account_name}"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

# Gateway API standard CRDs. Skip when the cluster already has them (another controller,
# or a platform team owns them).
resource "helm_release" "gateway_api_crds" {
  count = var.install_gateway_api_crds ? 1 : 0

  name      = "gateway-api-crds"
  chart     = "${path.module}/charts/gateway-api-crds"
  namespace = var.namespace
}

resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace
  timeout    = 600

  values = [yamlencode({
    clusterName  = var.cluster_name
    region       = var.region
    vpcId        = var.vpc_id
    replicaCount = 2
    serviceAccount = {
      create = true
      name   = local.service_account_name
      annotations = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.this.arn
      }
    }
    podDisruptionBudget = {
      maxUnavailable = 1
    }
    # Only Services that ask for the controller get an NLB from it.
    enableServiceMutatorWebhook = false
    controllerConfig = {
      featureGates = {
        ALBGatewayAPI = true
        # Apigene needs no L4 (NLB) Gateways.
        NLBGatewayAPI = false
      }
    }
  })]

  depends_on = [
    aws_iam_role_policy_attachment.this,
    helm_release.gateway_api_crds,
  ]
}

resource "helm_release" "gateway_class" {
  name      = "gateway-class-${var.gateway_class_name}"
  chart     = "${path.module}/charts/gateway-class"
  namespace = var.namespace

  set {
    name  = "name"
    value = var.gateway_class_name
  }

  depends_on = [helm_release.this]
}
