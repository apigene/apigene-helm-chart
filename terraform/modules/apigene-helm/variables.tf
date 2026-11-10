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
  description = "Apigene image tag for all services. Empty uses the chart appVersion."
  type        = string
  default     = ""
}

variable "auth_secret_key" {
  description = "AUTH_APIGENE_SECRET_KEY value. Leave empty to auto-generate."
  type        = string
  default     = ""
  sensitive   = true
}

variable "cluster_issuer_name" {
  description = "cert-manager ClusterIssuer name for ingress TLS (ingress-nginx only)."
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
  description = "Apigene deployment type (SaaS or OnPrem)."
  type        = string
  default     = "SaaS"
}

variable "license_public_key" {
  description = "OnPrem only — PEM or base64:… public key to verify pasted licenses. Empty = trial mode."
  type        = string
  default     = ""
  sensitive   = true
}

variable "license_algorithm" {
  description = "OnPrem license JWT algorithm (default RS256)."
  type        = string
  default     = "RS256"
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

variable "ingress_class_name" {
  description = "IngressClass: \"alb\" (AWS Load Balancer Controller) or \"nginx\" (ingress-nginx)."
  type        = string
  default     = "nginx"
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB (ingress_class_name = alb)."
  type        = string
  default     = ""
}

variable "alb_group_name" {
  description = "ALB IngressGroup name; also tags the ALB so Terraform can find it."
  type        = string
  default     = ""
}

variable "alb_inbound_cidrs" {
  description = "CIDRs allowed to reach the ALB. Empty allows 0.0.0.0/0."
  type        = list(string)
  default     = []
}

variable "waf_acl_arn" {
  description = "AWS WAFv2 web ACL ARN to attach to the ALB."
  type        = string
  default     = ""
}

variable "alb_tags" {
  description = "AWS tags for the ALB."
  type        = map(string)
  default     = {}
}

variable "mongo_auth" {
  description = "Require a password for the bundled MongoDB (generated)."
  type        = bool
  default     = true
}

variable "mongo_backup" {
  description = "Run the nightly mongodump CronJob for the bundled MongoDB."
  type        = bool
  default     = true
}

variable "redis_auth" {
  description = "Require a password for the bundled Redis (generated)."
  type        = bool
  default     = true
}

variable "app_replicas" {
  description = "Replicas for backend, copilot, mcp-gw and nginx."
  type        = number
  default     = 1
}

variable "expose_api_docs" {
  description = "Serve /docs, /redoc and /openapi.json publicly."
  type        = bool
  default     = false
}

variable "network_policy_ingress_cidrs" {
  description = "Enable NetworkPolicy and allow these CIDRs to nginx (the VPC CIDR for an ALB)."
  type        = list(string)
  default     = []
}

variable "network_policy_ingress_namespace_labels" {
  description = "Enable NetworkPolicy and allow the ingress controller namespace with these labels."
  type        = map(string)
  default     = {}
}

variable "service_account_annotations" {
  description = "Annotations for the Apigene service account (IRSA role ARN)."
  type        = map(string)
  default     = {}
}
