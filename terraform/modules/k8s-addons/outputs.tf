output "cluster_issuer_name" {
  value = local.cluster_issuer_name
}

output "ingress_hostname" {
  description = "Hostname of the ingress LoadBalancer (AWS NLB DNS name when aws_nlb=true)."
  value       = try(data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].hostname, "")
}

output "ingress_ip" {
  description = "IP of the ingress LoadBalancer when available."
  value       = try(data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip, "")
}

output "ingress_namespace" {
  value = var.ingress_namespace
}
