# Alias record for the Apigene hostname, pointing at the load balancer.

resource "aws_route53_record" "apigene" {
  zone_id = var.hosted_zone_id
  name    = var.fqdn
  type    = "A"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "apigene_ipv6" {
  count = var.ipv6 ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.fqdn
  type    = "AAAA"

  alias {
    name                   = var.load_balancer_dns_name
    zone_id                = var.load_balancer_zone_id
    evaluate_target_health = true
  }
}
