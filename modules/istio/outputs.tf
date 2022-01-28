output "istio_namespace" {
  value = var.istio_namespace
}

output "istio_ing_gw" {
  value = data.kubernetes_service.istio_ingress_gateway
}

output "prometheus" {
  value = data.kubernetes_service.prometheus
}

output "prometheus_url" {
  value = "http://${data.kubernetes_service.prometheus.metadata[0].name}:${data.kubernetes_service.prometheus.spec[0].port[index(data.kubernetes_service.prometheus.spec[0].port.*.name, "http")].port}"
  # value = index(data.kubernetes_service.prometheus.spec[0].port.*.name, "http")
}
