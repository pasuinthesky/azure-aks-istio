terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.3.0"
    }
  }
}


locals {
  kubeconfig_path = ".kube/${var.aks_cluster_name}-certmgr"
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

provider helm {
  kubernetes {
    host                   = local.k8s_host
    client_certificate     = base64decode(local.k8s_client_certificate)
    client_key             = base64decode(local.k8s_client_key)
    cluster_ca_certificate = base64decode(local.k8s_cluster_ca_certificate)
  }
}

provider kubectl {
  load_config_file       = "false"
  host                   = local.k8s_host
  client_certificate     = base64decode(local.k8s_client_certificate)
  client_key             = base64decode(local.k8s_client_key)
  cluster_ca_certificate = base64decode(local.k8s_cluster_ca_certificate)
}

provider azurerm {
  features {}
}

resource "null_resource" "dependency" {
  triggers = {
    dependency_id = var.aks_cluster_name
  }
}

resource "kubernetes_namespace" "cert_manager" {
  depends_on = [ null_resource.dependency ]
  metadata {
    name = "cert-manager"
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "1.3.1"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  set {
    name  = "installCRDs"
    value = "true"
  }
  set {
    name  = "extraArgs"
    value = "{--dns01-recursive-nameservers-only,--dns01-recursive-nameservers=${replace(trimsuffix("%{ for i in var.dns_zone.name_servers }${trimsuffix(i, ".")}:53,%{ endfor }", ","), ",", "\\,")}}"
  }
}

data "azurerm_key_vault" "this" {
  name         = var.vault_name
  resource_group_name = var.vault_rg_name
}

data "azurerm_key_vault_secret" "client_id" {
  name         = var.sp_id_keyname
  key_vault_id = data.azurerm_key_vault.this.id
}
data "azurerm_key_vault_secret" "client_secret" {
  name         = var.sp_secret_keyname
  key_vault_id = data.azurerm_key_vault.this.id
}
resource "kubernetes_secret" "secret" {
  metadata {
    name      = "cert-manager-dns-config-secret"
    namespace = kubernetes_namespace.cert_manager.id
  }
  data = {
    # Azure DNS client secret (for Azure DNS)
    CLIENT_SECRET = data.azurerm_key_vault_secret.client_secret.value
  }
}

data azurerm_client_config current {}

data "template_file" "cert_manager_clusterissuer" {
  template = file("files/cert-manager-azure-clusterissuer.yaml.tmpl")
  vars = {
    email          = "glen.liu@cautiontape.ca"
    hostedZoneName = var.dns_zone.name
    # Azure DNS access credentials (for Azure DNS)
    clientID                = data.azurerm_key_vault_secret.client_id.value
    resourceGroupName       = var.rg_name
    resource_group_name_dns = var.rg_name
    subscriptionID          = data.azurerm_client_config.current.subscription_id
    tenantID                = data.azurerm_client_config.current.tenant_id
  }
}
data "kubectl_file_documents" "cert_manager_clusterissuer" {
  content = data.template_file.cert_manager_clusterissuer.rendered
}
resource "kubectl_manifest" "cert_manager_clusterissuer" {
  depends_on = [helm_release.cert_manager]
  for_each   = data.kubectl_file_documents.cert_manager_clusterissuer.manifests
  yaml_body  = each.value
}

data "template_file" "cert_manager_certificate_production" {
  template = file("files/cert-manager-certificate.yaml.tmpl")
  vars = {
    dnsName                 = var.dns_zone.name
    letsencrypt_environment = "production"
  }
}
data "kubectl_file_documents" "cert_manager_certificate_production" {
  content = data.template_file.cert_manager_certificate_production.rendered
}
resource "kubectl_manifest" "cert_manager_certificate_production" {
  depends_on = [kubectl_manifest.cert_manager_certificate_production]
  for_each   = data.kubectl_file_documents.cert_manager_certificate_production.manifests
  yaml_body  = each.value
}

data "template_file" "cert_manager_certificate_staging" {
  template = file("files/cert-manager-certificate.yaml.tmpl")
  vars = {
    dnsName                 = var.dns_zone.name
    letsencrypt_environment = "staging"
  }
}
data "kubectl_file_documents" "cert_manager_certificate_staging" {
  content = data.template_file.cert_manager_certificate_staging.rendered
}
resource "kubectl_manifest" "cert_manager_certificate_staging" {
  depends_on = [kubectl_manifest.cert_manager_certificate_staging]
  for_each   = data.kubectl_file_documents.cert_manager_certificate_staging.manifests
  yaml_body  = each.value
}

# resource "null_resource" "cert_manager_certificate_label_production" {
#   depends_on = [ kubectl_manifest.cert_manager_certificate_production ]

#   triggers = {
#     env_name   = "production"
#     kubeconfig = local.kubeconfig_path # Variables cannot be accessed by destroy-phase provisioners, only the 'self' object (including triggers)
#   }

#   provisioner "local-exec" {
#     command = "kubectl wait --kubeconfig=\"${self.triggers.kubeconfig}\" --for=condition=ready -n cert-manager certificate/ingress-cert-${self.triggers.env_name} --timeout=10m && kubectl annotate --kubeconfig=${self.triggers.kubeconfig} secret ingress-cert-${self.triggers.env_name} -n cert-manager kubed.appscode.com/sync='app=kubed'"
#   }

#   provisioner "local-exec" {
#     when    = destroy
#     command = "kubectl annotate secret --kubeconfig=\"${self.triggers.kubeconfig}\" ingress-cert-${self.triggers.env_name} -n cert-manager kubed.appscode.com/sync-"
#   }
# }


# resource "null_resource" "cert_manager_certificate_label_staging" {
#   depends_on = [ kubectl_manifest.cert_manager_certificate_staging ]

#   triggers = {
#     env_name   = "staging"
#     kubeconfig = local.kubeconfig_path # Variables cannot be accessed by destroy-phase provisioners, only the 'self' object (including triggers)
#   }

#   provisioner "local-exec" {
#     command = "kubectl wait --kubeconfig=\"${self.triggers.kubeconfig}\" --for=condition=ready -n cert-manager certificate/ingress-cert-${self.triggers.env_name} --timeout=10m && kubectl annotate --kubeconfig=${self.triggers.kubeconfig} secret ingress-cert-${self.triggers.env_name} -n cert-manager kubed.appscode.com/sync='app=kubed'"
#   }

#   provisioner "local-exec" {
#     when    = destroy
#     command = "kubectl annotate secret --kubeconfig=\"${self.triggers.kubeconfig}\" ingress-cert-${self.triggers.env_name} -n cert-manager kubed.appscode.com/sync-"
#   }
# }
