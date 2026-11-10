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

output "mongo_password" {
  value     = try(random_password.mongo[0].result, "")
  sensitive = true
}

output "redis_password" {
  value     = try(random_password.redis[0].result, "")
  sensitive = true
}
