variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-central-1"
}

variable "tenant_name" {
  description = "Tenant name used as a prefix for resources and Apigene config."
  type        = string

  # DNS label, short enough for the ALB name apigene-<tenant> (32 characters max).
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$", var.tenant_name))
    error_message = "tenant_name: 1-24 lowercase letters, digits and hyphens, not starting or ending with a hyphen."
  }
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

variable "image_tag" {
  description = "Apigene image tag. Empty uses the chart appVersion (pinned release)."
  type        = string
  default     = ""
}

variable "auth_secret_key" {
  description = "Optional AUTH_APIGENE_SECRET_KEY. Auto-generated when empty."
  type        = string
  default     = ""
  sensitive   = true
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

variable "alb_inbound_cidrs" {
  description = "CIDRs allowed to reach the ALB. Empty allows the internet (0.0.0.0/0)."
  type        = list(string)
  default     = []
}

variable "waf_acl_arn" {
  description = "Optional AWS WAFv2 regional web ACL ARN for the ALB."
  type        = string
  default     = ""
}

variable "app_replicas" {
  description = "Replicas for backend, copilot, mcp-gw and nginx (2+ for production)."
  type        = number
  default     = 2
}

variable "expose_api_docs" {
  description = "Serve /docs, /redoc and /openapi.json publicly."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway. Set false for one per AZ (production)."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = false
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Narrow to your admin networks."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
