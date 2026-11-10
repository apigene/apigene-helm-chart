variable "hosted_zone_id" {
  description = "Route53 hosted zone ID."
  type        = string
}

variable "fqdn" {
  description = "Fully qualified domain name for the Apigene deployment."
  type        = string
}

variable "load_balancer_dns_name" {
  description = "DNS name of the load balancer to alias (ALB or NLB)."
  type        = string
}

variable "load_balancer_zone_id" {
  description = "Canonical hosted zone ID of the load balancer."
  type        = string
}

variable "ipv6" {
  description = "Also create an AAAA alias (dual-stack load balancer only)."
  type        = bool
  default     = false
}
