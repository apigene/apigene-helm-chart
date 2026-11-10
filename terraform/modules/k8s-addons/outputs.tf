output "cluster_issuer_name" {
  description = "Let's Encrypt ClusterIssuer name (empty without cert-manager)."
  value       = var.install_cert_manager ? local.cluster_issuer_name : ""
}

output "ingress_hostname" {
  description = "Hostname of the ingress-nginx LoadBalancer (AWS NLB DNS name when aws_nlb=true)."
  value       = try(data.kubernetes_service.ingress_nginx[0].status[0].load_balancer[0].ingress[0].hostname, "")
}

output "ingress_ip" {
  description = "IP of the ingress-nginx LoadBalancer when available."
  value       = try(data.kubernetes_service.ingress_nginx[0].status[0].load_balancer[0].ingress[0].ip, "")
}

output "ingress_namespace" {
  value = var.ingress_namespace
}
