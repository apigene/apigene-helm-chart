data "aws_route53_zone" "this" {
  zone_id = var.hosted_zone_id
}

resource "aws_route53_record" "apigene" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = var.fqdn
  type    = "A"

  alias {
    name                   = var.load_balancer_hostname
    zone_id                = data.aws_lb_hosted_zone_id.nlb.id
    evaluate_target_health = true
  }
}

data "aws_lb_hosted_zone_id" "nlb" {
  load_balancer_type = "network"
}
