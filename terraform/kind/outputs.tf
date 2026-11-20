output "namespace" {
  description = "Isolated namespace managed by Terraform. Existing 'opsforge' is not modified."
  value       = kubernetes_namespace_v1.opsforge.metadata[0].name
}

output "api_port_forward" {
  description = "Run in a separate terminal after a successful apply."
  value       = "kubectl --context kind-opsforge -n ${local.namespace} port-forward svc/opsforge-api 8082:8000"
}

output "health_url" {
  value = "http://127.0.0.1:8082/health/ready"
}
