variable "fqdn" {
  description = "Hostname the certificate covers."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for the validation record."
  type        = string
}

variable "tags" {
  description = "Tags applied to the certificate."
  type        = map(string)
  default     = {}
}
