variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "region" {
  description = "AWS region of the cluster."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID of the cluster."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN of the cluster (IRSA)."
  type        = string
}

variable "oidc_issuer_url" {
  description = "OIDC issuer URL of the cluster."
  type        = string
}

variable "namespace" {
  description = "Namespace for the controller."
  type        = string
  default     = "kube-system"
}

variable "chart_version" {
  description = "aws-load-balancer-controller Helm chart version. Update iam_policy.json with it."
  type        = string
  default     = "3.6.2"
}

variable "tags" {
  description = "Tags applied to IAM resources."
  type        = map(string)
  default     = {}
}

variable "install_gateway_api_crds" {
  description = "Install the Gateway API standard CRDs (v1.6.1). Set false when the cluster already has them."
  type        = bool
  default     = true
}

variable "gateway_class_name" {
  description = "Name of the GatewayClass for ALB Gateways (controllerName gateway.k8s.aws/alb)."
  type        = string
  default     = "alb"
}
