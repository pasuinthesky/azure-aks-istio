terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

# provider azurerm {
#   features {}
# }
locals {
  kubeconfig_path = ".kube/${var.aks_cluster_name}-istio"
  k8s_adm_cred = sensitive(yamldecode(var.kubeconfig_raw))
  k8s_host = sensitive(local.k8s_adm_cred.clusters.0.cluster.server)
  k8s_client_certificate = sensitive(local.k8s_adm_cred.users.0.user.client-certificate-data)
  k8s_client_key = sensitive(local.k8s_adm_cred.users.0.user.client-key-data)
  k8s_cluster_ca_certificate = sensitive(local.k8s_adm_cred.clusters.0.cluster.certificate-authority-data)
}

resource "local_file" "kube_config" {
  sensitive_content  = var.kubeconfig_raw
  filename = local.kubeconfig_path
  file_permission = "0600"
}

provider kubernetes {
  host                   = local.k8s_host
  client_certificate     = base64decode(local.k8s_client_certificate)
  client_key             = base64decode(local.k8s_client_key)
  cluster_ca_certificate = base64decode(local.k8s_cluster_ca_certificate)
}

provider kubectl {
  load_config_file       = "false"
  host                   = local.k8s_host
  client_certificate     = base64decode(local.k8s_client_certificate)
  client_key             = base64decode(local.k8s_client_key)
  cluster_ca_certificate = base64decode(local.k8s_cluster_ca_certificate)
}

resource "null_resource" "dependency" {
  triggers = {
    dependency_id = var.aks_cluster_name
  }
}

resource "kubernetes_namespace" "istio_system" {
  metadata {
    name = var.istio_namespace
  }
  depends_on = [ null_resource.dependency ]
}

resource "random_password" "password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "kubernetes_secret" "grafana" {
  metadata {
    name      = "grafana"
    namespace = var.istio_namespace
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
  metadata {
    name      = "kiali"
    namespace = var.istio_namespace
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
    kubeconfig_file_name = local.kubeconfig_path
  }
  provisioner "local-exec" {
    command = "istioctl operator init --kubeconfig \"${self.triggers.kubeconfig_file_name}\""
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = "istioctl operator remove --kubeconfig \"${self.triggers.kubeconfig_file_name}\""
  }

  depends_on = [kubernetes_secret.grafana, kubernetes_secret.kiali, local_file.kube_config]
}


resource "kubectl_manifest" "istio_operator" {
  yaml_body  = <<YAML
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  namespace: ${var.istio_namespace}
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

data "kubernetes_service" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = var.istio_namespace
  }
  depends_on = [kubectl_manifest.istio_operator]
}

data "kubernetes_service" "istio_ingress_gateway" {
  metadata {
    name      = var.istio_ingress_gateway
    namespace = var.istio_namespace
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
data "kubectl_path_documents" "sample_app" {
  count = var.deploy_sample_app ? 1 : 0
  pattern = var.sample_app_path
}

// source of booking info application - https://istio.io/latest/docs/examples/bookinfo/

resource "kubectl_manifest" "sample_app" {
  for_each   = toset(data.kubectl_path_documents.sample_app[0].documents)
  yaml_body  = each.value
  depends_on = [kubectl_manifest.istio_operator, data.kubectl_path_documents.sample_app]
}
