output "release_name" {
  value = helm_release.apigene.name
}

output "namespace" {
  value = helm_release.apigene.namespace
}

output "public_url" {
  value = local.public_url
}

output "auth_secret_key" {
  value     = local.auth_secret_key
  sensitive = true
}

output "fqdn" {
  value = var.fqdn
}
