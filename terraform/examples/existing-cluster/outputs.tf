output "public_url" {
  description = "Public URL for the Apigene deployment."
  value       = module.apigene.public_url
}

output "namespace" {
  description = "Kubernetes namespace for Apigene."
  value       = module.apigene.namespace
}

output "auth_secret_key" {
  description = "Generated AUTH_APIGENE_SECRET_KEY (store securely)."
  value       = module.apigene.auth_secret_key
  sensitive   = true
}

output "gateway_address_command" {
  description = "Prints the Gateway address to point DNS at."
  value       = "kubectl get gateway apigene -n ${module.apigene.namespace} -o jsonpath='{.status.addresses[0].value}'"
}
