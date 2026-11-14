variable "name" {
  description = "Prefix for VPC resources."
  type        = string
}

variable "cidr_block" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones for subnets."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to all VPC resources."
  type        = map(string)
  default     = {}
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper). Set false for one NAT gateway per AZ in production."
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = false
}

variable "flow_logs_retention_days" {
  description = "Retention for VPC flow logs."
  type        = number
  default     = 90
}
