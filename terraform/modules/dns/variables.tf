variable "hosted_zone_id" {
  description = "Route53 hosted zone ID."
  type        = string
}

variable "fqdn" {
  description = "Fully qualified domain name for the Apigene deployment."
  type        = string
}

variable "load_balancer_hostname" {
  description = "Load balancer hostname to alias (nginx ingress NLB)."
  type        = string
}

variable "ttl" {
  description = "TTL for non-alias records (unused for alias records)."
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags applied to DNS resources."
  type        = map(string)
  default     = {}
}
