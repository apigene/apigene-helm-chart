variable "release_name" {
  description = "Helm release name."
  type        = string
  default     = "apigene"
}

variable "namespace" {
  description = "Kubernetes namespace for Apigene."
  type        = string
  default     = "apigene"
}

variable "chart_path" {
  description = "Path to the Apigene Helm chart directory."
  type        = string
}

variable "tenant_name" {
  description = "Logical tenant name passed to Apigene containers."
  type        = string
}

variable "fqdn" {
  description = "Public hostname for ingress and publicUrl."
  type        = string
}

variable "image_tag" {
  description = "Apigene image tag for all services."
  type        = string
  default     = "5.2.0"
}

variable "auth_secret_key" {
  description = "AUTH_APIGENE_SECRET_KEY value. Leave empty to auto-generate."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cluster_issuer_name" {
  description = "cert-manager ClusterIssuer name for ingress TLS."
  type        = string
  default     = "letsencrypt-prod"
}

variable "enable_tls" {
  description = "Enable TLS on the ingress."
  type        = bool
  default     = true
}

variable "storage_class" {
  description = "StorageClass for MongoDB PVC."
  type        = string
  default     = ""
}

variable "mongo_storage" {
  description = "MongoDB PVC size."
  type        = string
  default     = "20Gi"
}

variable "deployment_type" {
  description = "Apigene deployment type label."
  type        = string
  default     = "SaaS"
}

variable "database_env" {
  description = "Apigene database environment label."
  type        = string
  default     = "production"
}

variable "wait" {
  description = "Wait for Helm release to become ready."
  type        = bool
  default     = true
}

variable "timeout" {
  description = "Helm install/upgrade timeout in seconds."
  type        = number
  default     = 1200
}

variable "public_url_port" {
  description = "Optional port appended to publicUrl (e.g. 8080 for local port-forward)."
  type        = number
  default     = 0
}

variable "copilot_internal_public_url_host_alias" {
  description = "Map publicUrl hostname to in-cluster nginx IP on the copilot pod (local k8s dev)."
  type        = bool
  default     = false
}

variable "extra_values" {
  description = "Additional Helm values merged on top of defaults."
  type        = map(any)
  default     = {}
}
