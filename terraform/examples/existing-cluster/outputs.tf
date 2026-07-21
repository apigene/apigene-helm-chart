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

output "ingress_hostname" {
  description = "Ingress LoadBalancer hostname when addons are installed."
  value       = var.install_addons ? module.k8s_addons[0].ingress_hostname : ""
}
