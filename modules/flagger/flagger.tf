terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.3.0"
    }
  }
}

locals {
  k8s_adm_cred = sensitive(yamldecode(var.kubeconfig_raw))
  k8s_host = sensitive(local.k8s_adm_cred.clusters.0.cluster.server)
  k8s_client_certificate = sensitive(local.k8s_adm_cred.users.0.user.client-certificate-data)
  k8s_client_key = sensitive(local.k8s_adm_cred.users.0.user.client-key-data)
  k8s_cluster_ca_certificate = sensitive(local.k8s_adm_cred.clusters.0.cluster.certificate-authority-data)
}

resource "null_resource" "dependency" {
  triggers = {
    dependency_id = var.prometheus_url
  }
}

provider helm { 
  kubernetes {
    host                   = local.k8s_host
    client_certificate     = base64decode(local.k8s_client_certificate)
    client_key             = base64decode(local.k8s_client_key)
    cluster_ca_certificate = base64decode(local.k8s_cluster_ca_certificate)
  }
}

resource "helm_release" "flagger" {
  depends_on = [ null_resource.dependency ]
  name       = "flagger"
  repository = "https://flagger.app"
  chart      = "flagger"
  namespace  = var.istio_namespace

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
    value = var.prometheus_url
  }
}
