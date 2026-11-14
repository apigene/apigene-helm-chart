variable "kubeconfig_path" {
  description = "Path to kubeconfig for the target cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Optional kubeconfig context name."
  type        = string
  default     = ""
}

variable "tenant_name" {
  description = "Tenant name passed to Apigene containers."
  type        = string
  default     = "local"
}

variable "fqdn" {
  description = "Hostname users open (Gateway listener and publicUrl)."
  type        = string
  default     = "apigene.localtest"
}

variable "image_tag" {
  description = "Apigene image tag."
  type        = string
  default     = ""
}

variable "auth_secret_key" {
  description = "Optional AUTH_APIGENE_SECRET_KEY. Auto-generated when empty."
  type        = string
  default     = ""
  sensitive   = true
}

variable "install_addons" {
  description = "Install Envoy Gateway (Gateway API) and cert-manager via Terraform."
  type        = bool
  default     = true
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt registration when install_addons=true."
  type        = string
  default     = "admin@example.com"
}

variable "use_staging_issuer" {
  description = "Use Let's Encrypt staging issuer."
  type        = bool
  default     = true
}

variable "enable_tls" {
  description = "Serve HTTPS on the Gateway with a Let's Encrypt certificate (disable for pure HTTP local testing)."
  type        = bool
  default     = false
}

variable "cluster_issuer_name" {
  description = "cert-manager ClusterIssuer when install_addons=false."
  type        = string
  default     = "letsencrypt-prod"
}

variable "gateway_class_name" {
  description = "GatewayClass of the cluster's Gateway API implementation when install_addons=false."
  type        = string
  default     = "eg"
}

variable "gateway_service_type" {
  description = "Service type for the Envoy Gateway proxies when install_addons=true: LoadBalancer, or NodePort without a load balancer implementation."
  type        = string
  default     = "LoadBalancer"
}

variable "install_storage_class" {
  description = "Create gp3 StorageClass (requires EBS CSI on AWS EKS)."
  type        = bool
  default     = false
}

variable "public_url_port" {
  description = "Port for publicUrl when using port-forward (local dev)."
  type        = number
  default     = 8080
}

variable "copilot_internal_public_url_host_alias" {
  description = "Resolve publicUrl hostname to in-cluster nginx from the copilot pod."
  type        = bool
  default     = true
}
