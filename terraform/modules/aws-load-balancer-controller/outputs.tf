output "role_arn" {
  description = "IAM role assumed by the controller."
  value       = aws_iam_role.this.arn
}

output "release_name" {
  value = helm_release.this.name
}

output "gateway_class_name" {
  description = "GatewayClass to put on the Apigene Gateway."
  value       = var.gateway_class_name
  # Consumers wait for the class (and the controller behind it) to exist.
  depends_on = [helm_release.gateway_class]
}
