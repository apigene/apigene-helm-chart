output "fqdn" {
  value = var.fqdn
}

output "record_fqdn" {
  value = aws_route53_record.apigene.fqdn
}

output "record_name" {
  value = aws_route53_record.apigene.name
}
