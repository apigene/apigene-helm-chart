output "cluster_issuer_name" {
  description = "Let's Encrypt ClusterIssuer name (empty without cert-manager)."
  value       = var.install_cert_manager ? local.cluster_issuer_name : ""
}

output "gateway_class_name" {
  description = "Envoy Gateway GatewayClass for the Apigene Gateway (empty without Envoy Gateway)."
  value       = var.install_envoy_gateway ? var.gateway_class_name : ""
  depends_on  = [helm_release.envoy_gateway_class]
}

output "gateway_namespace" {
  description = "Namespace of the Envoy proxies (allow it in the Apigene NetworkPolicy)."
  value       = var.envoy_gateway_namespace
}
