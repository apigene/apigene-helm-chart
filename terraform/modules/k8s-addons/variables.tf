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
  description = "Email address for Let's Encrypt registration."
  type        = string
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
