resource "kubernetes_namespace" "istio_system" {
  provider = kubernetes.local
  metadata {
    name = "istio-system"
  }
}

resource "kubernetes_secret" "grafana" {
  provider = kubernetes.local
  metadata {
    name      = "grafana"
    namespace = "istio-system"
    labels = {
      app = "grafana"
    }
  }
  data = {
    username   = "admin"
    passphrase = random_password.password.result
  }
  type       = "Opaque"
  depends_on = [kubernetes_namespace.istio_system]
}

resource "kubernetes_secret" "kiali" {
  provider = kubernetes.local
  metadata {
    name      = "kiali"
    namespace = "istio-system"
    labels = {
      app = "kiali"
    }
  }
  data = {
    username   = "admin"
    passphrase = random_password.password.result
  }
  type       = "Opaque"
  depends_on = [kubernetes_namespace.istio_system]
}

resource "null_resource" "istio" {
  triggers = {
    always_run = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "istioctl operator init --kubeconfig \".kube/${azurerm_kubernetes_cluster.aks.name}\""
  }
  #depends_on = [kubernetes_secret.grafana, kubernetes_secret.kiali, local_file.istio-config]
  depends_on = [helm_release.cert_manager]
}


resource "kubectl_manifest" "istio_operator" {
  yaml_body  = <<YAML
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: istio-system
  name: example-istiocontrolplane
spec:
  profile: demo
YAML
  depends_on = [null_resource.istio]
}

data "http" "grafana" {
  url = "https://raw.githubusercontent.com/istio/istio/master/samples/addons/grafana.yaml"
}
data "kubectl_file_documents" "grafana" {
  content = data.http.grafana.body
}
resource "kubectl_manifest" "grafana" {
  for_each   = data.kubectl_file_documents.grafana.manifests
  yaml_body  = each.value
  depends_on = [kubectl_manifest.istio_operator]
}

data "http" "kiali" {
  url = "https://raw.githubusercontent.com/istio/istio/master/samples/addons/kiali.yaml"
}
data "kubectl_file_documents" "kiali" {
  content = data.http.kiali.body
}
resource "kubectl_manifest" "kiali" {
  for_each   = data.kubectl_file_documents.kiali.manifests
  yaml_body  = each.value
  depends_on = [kubectl_manifest.istio_operator]
}
data "http" "prometheus" {
  url = "https://raw.githubusercontent.com/istio/istio/master/samples/addons/prometheus.yaml"
}
data "kubectl_file_documents" "prometheus" {
  content = data.http.prometheus.body
}
resource "kubectl_manifest" "prometheus" {
  for_each   = data.kubectl_file_documents.prometheus.manifests
  yaml_body  = each.value
  depends_on = [kubectl_manifest.istio_operator]
}
data "http" "jaeger" {
  url = "https://raw.githubusercontent.com/istio/istio/master/samples/addons/jaeger.yaml"
}
data "kubectl_file_documents" "jaeger" {
  content = data.http.jaeger.body
}
resource "kubectl_manifest" "jaeger" {
  for_each   = data.kubectl_file_documents.jaeger.manifests
  yaml_body  = each.value
  depends_on = [kubectl_manifest.istio_operator]
}

data "kubernetes_service" "istio_ingress_gateway" {
  provider = kubernetes.local
  metadata {
    name      = "istio-ingressgateway"
    namespace = "istio-system"
  }
  depends_on = [kubectl_manifest.istio_operator]
}
# resource "azurerm_dns_a_record" "myapp" {
#   name                = "myapp"
#   zone_name           = azurerm_dns_zone.azaks_dev.name
#   resource_group_name = azurerm_resource_group.rg.name
#   ttl                 = 300
#   records             = data.kubernetes_service.istio_ingress_gateway
# }

################### Deploy booking info sample application with gateway  #######################################

// kubectl provider can be installed from here - https://gavinbunney.github.io/terraform-provider-kubectl/docs/provider.html 
data "kubectl_path_documents" "manifests" {
  pattern = "samples/bookinfo/*.yaml"
}

// source of booking info application - https://istio.io/latest/docs/examples/bookinfo/

resource "kubectl_manifest" "bookinginfo" {
  for_each   = toset(data.kubectl_path_documents.manifests.documents)
  yaml_body  = each.value
  depends_on = [kubectl_manifest.istio_operator]
}

output "istio" {
  value = data.kubernetes_service.istio_ingress_gateway
}
