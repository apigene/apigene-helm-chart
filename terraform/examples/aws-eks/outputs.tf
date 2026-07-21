output "apigene_url" {
  description = "Public HTTPS URL for the Apigene deployment."
  value       = module.apigene.public_url
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "fqdn" {
  description = "DNS name for the deployment."
  value       = local.fqdn
}

output "nginx_lb_hostname" {
  description = "nginx-ingress LoadBalancer hostname."
  value       = module.k8s_addons.ingress_hostname
}

output "auth_secret_key" {
  description = "Generated AUTH_APIGENE_SECRET_KEY (store securely)."
  value       = module.apigene.auth_secret_key
  sensitive   = true
}

output "namespace" {
  description = "Kubernetes namespace for Apigene."
  value       = module.apigene.namespace
}
