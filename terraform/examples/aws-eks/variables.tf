variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-central-1"
}

variable "tenant_name" {
  description = "Tenant name used as a prefix for resources and Apigene config."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = ""
}

variable "root_domain" {
  description = "Root DNS zone (e.g. apigene.ai)."
  type        = string
  default     = "apigene.ai"
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for root_domain."
  type        = string
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate registration."
  type        = string
}

variable "image_tag" {
  description = "Apigene image tag."
  type        = string
  default     = "5.2.0"
}

variable "auth_secret_key" {
  description = "Optional AUTH_APIGENE_SECRET_KEY. Auto-generated when empty."
  type        = string
  default     = ""
  sensitive   = true
}

variable "use_staging_issuer" {
  description = "Use Let's Encrypt staging issuer (for testing)."
  type        = bool
  default     = false
}

variable "vpc_cidr_block" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_types" {
  description = "EC2 instance types for EKS nodes."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "Desired EKS node count."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum EKS node count."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum EKS node count."
  type        = number
  default     = 4
}

variable "tags" {
  description = "Additional tags for AWS resources."
  type        = map(string)
  default     = {}
}
