variable "install_envoy_gateway" {
  description = "Install Envoy Gateway (Gateway API implementation and CRDs) with a GatewayClass. Use for non-AWS clusters; on EKS use the AWS Load Balancer Controller."
  type        = bool
  default     = true
}

variable "envoy_gateway_chart_version" {
  description = "Envoy Gateway Helm chart version (oci://docker.io/envoyproxy/gateway-helm)."
  type        = string
  default     = "v1.10.0"
}

variable "envoy_gateway_namespace" {
  description = "Namespace for Envoy Gateway and its Gateway proxies."
  type        = string
  default     = "envoy-gateway-system"
}

variable "gateway_class_name" {
  description = "Name of the Envoy Gateway GatewayClass."
  type        = string
  default     = "eg"
}

variable "gateway_service_type" {
  description = "Service type in front of each Gateway's Envoy proxies: LoadBalancer, or NodePort without a load balancer implementation."
  type        = string
  default     = "LoadBalancer"

  validation {
    condition     = contains(["LoadBalancer", "NodePort", "ClusterIP"], var.gateway_service_type)
    error_message = "gateway_service_type must be LoadBalancer, NodePort or ClusterIP."
  }
}

variable "gateway_service_annotations" {
  description = "Annotations for the Gateway proxy Service (e.g. MetalLB address pool)."
  type        = map(string)
  default     = {}
}

variable "install_cert_manager" {
  description = "Install cert-manager (Gateway API mode) and a Let's Encrypt ClusterIssuer."
  type        = bool
  default     = true
}

variable "cert_manager_chart_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "v1.21.3"
}

variable "cert_manager_namespace" {
  description = "Namespace for cert-manager."
  type        = string
  default     = "cert-manager"
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt registration (install_cert_manager only)."
  type        = string
  default     = ""
}

variable "use_staging_issuer" {
  description = "Use the Let's Encrypt staging environment (no rate limits; untrusted certificates)."
  type        = bool
  default     = false
}

variable "acme_gateway_name" {
  description = "Gateway whose HTTP listener serves Let's Encrypt HTTP-01 challenges (the Apigene release fullname)."
  type        = string
  default     = "apigene"
}

variable "acme_gateway_namespace" {
  description = "Namespace of that Gateway (the Apigene release namespace)."
  type        = string
  default     = "apigene"
}

variable "install_storage_class" {
  description = "Create a default gp3 StorageClass for EBS volumes."
  type        = bool
  default     = true
}
