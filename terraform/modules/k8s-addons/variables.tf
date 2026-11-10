variable "ingress_namespace" {
  description = "Namespace for ingress-nginx."
  type        = string
  default     = "ingress-nginx"
}

variable "cert_manager_namespace" {
  description = "Namespace for cert-manager."
  type        = string
  default     = "cert-manager"
}

variable "install_storage_class" {
  description = "Create a default gp3 StorageClass for EBS volumes."
  type        = bool
  default     = true
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt registration (install_cert_manager only)."
  type        = string
  default     = ""
}

variable "use_staging_issuer" {
  description = "Use Let's Encrypt staging issuer instead of production."
  type        = bool
  default     = false
}

variable "aws_nlb" {
  description = "Expose ingress-nginx via AWS Network Load Balancer."
  type        = bool
  default     = true
}

variable "ingress_wait_seconds" {
  description = "Seconds to wait for ingress-nginx LoadBalancer hostname."
  type        = number
  default     = 120
}

variable "install_ingress_nginx" {
  description = "Install ingress-nginx. Use for non-AWS clusters; on EKS use the AWS Load Balancer Controller."
  type        = bool
  default     = true
}

variable "ingress_nginx_chart_version" {
  description = "ingress-nginx Helm chart version."
  type        = string
  default     = "4.15.1"
}

variable "install_cert_manager" {
  description = "Install cert-manager and a Let's Encrypt ClusterIssuer (not needed with ALB + ACM)."
  type        = bool
  default     = true
}

variable "cert_manager_chart_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "v1.21.3"
}
