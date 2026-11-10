output "role_arn" {
  description = "IAM role assumed by the controller."
  value       = aws_iam_role.this.arn
}

output "release_name" {
  value = helm_release.this.name
}
