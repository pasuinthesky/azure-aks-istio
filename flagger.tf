resource "helm_release" "flagger" {
  depends_on = [kubectl_manifest.prometheus]
  name       = "flagger"
  repository = "https://flagger.app"
  chart      = "flagger"
  namespace  = kubernetes_namespace.istio_system.metadata[0].name

  set {
    name  = "crd.create"
    value = "false"
  }
  set {
    name  = "meshProvider"
    value = "istio"
  }
  set {
    name  = "metricsServer"
    value = "http://prometheus:9090"
  }
}
