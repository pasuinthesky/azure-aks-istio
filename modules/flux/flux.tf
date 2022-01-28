terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
    flux = {
      source  = "fluxcd/flux"
      version = ">= 0.0.13"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "3.1.0"
    }
  }
}

locals {
  kubeconfig_path = ".kube/${var.aks_cluster_name}-flux"
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

provider azurerm {
  features {}
}

resource "null_resource" "dependency" {
  triggers = {
    dependency_id = var.aks_cluster_name
  }
}

data "azurerm_key_vault" "this" {
  name         = var.vault_name
  resource_group_name = var.vault_rg_name
}

data "azurerm_key_vault_secret" "github_owner" {
  name         = "github-owner"
  key_vault_id = data.azurerm_key_vault.this.id
}
data "azurerm_key_vault_secret" "github_token" {
  name         = "github-token"
  key_vault_id = data.azurerm_key_vault.this.id
}
provider "github" {
  owner = data.azurerm_key_vault_secret.github_owner.value
  token = data.azurerm_key_vault_secret.github_token.value
}

# SSH
locals {
  known_hosts = "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
}

resource "tls_private_key" "main" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

# Flux
data "flux_install" "main" {
  target_path = var.target_path
}

data "flux_sync" "main" {
  target_path = var.target_path
  url         = "ssh://git@github.com/${data.azurerm_key_vault_secret.github_owner.value}/${var.repository_name}.git"
  branch      = var.branch
}

resource "null_resource" "flux_namespace" {
  depends_on = [ null_resource.dependency, local_file.kube_config ]

  triggers = {
    namespace  = var.flux_namespace
    kubeconfig = local.kubeconfig_path # Variables cannot be accessed by destroy-phase provisioners, only the 'self' object (including triggers)
  }

  provisioner "local-exec" {
    command = "kubectl --kubeconfig ${self.triggers.kubeconfig} create namespace ${self.triggers.namespace}"
  }

  /*
  Marking the flux-system namespace for deletion, will cause finalizers to be applied for any Flux CRDs in use. The finalize controllers however have been deleted, causing namespace and CRDs to be stuck 'terminating'.

  After marking the namespace for deletion, wait an abitrary amount of time for cascade delete to remove workloads managed by Flux.

  Finally remove any finalizers from Flux CRDs, allowing these and the namespace to transition from 'terminating' and actually be deleted.
  */

  provisioner "local-exec" {
    when       = destroy
    command    = "kubectl --kubeconfig ${self.triggers.kubeconfig} delete namespace ${self.triggers.namespace} --cascade=true --wait=false && sleep 120"
  }

  provisioner "local-exec" {
    when       = destroy
    command    = "kubectl --kubeconfig ${self.triggers.kubeconfig} patch customresourcedefinition helmcharts.source.toolkit.fluxcd.io helmreleases.helm.toolkit.fluxcd.io helmrepositories.source.toolkit.fluxcd.io kustomizations.kustomize.toolkit.fluxcd.io gitrepositories.source.toolkit.fluxcd.io -p '{\"metadata\":{\"finalizers\":null}}'"
    on_failure = continue
  }

}

# resource "kubernetes_namespace" "flux_system" {
#   metadata {
#     name = var.flux_namespace
#   }

#   lifecycle {
#     ignore_changes = [
#       metadata[0].labels,
#     ]
#   }
  
#   depends_on = [ null_resource.dependency ]
# }

data "kubectl_file_documents" "install" {
  content = data.flux_install.main.content
}

data "kubectl_file_documents" "sync" {
  content = data.flux_sync.main.content
}

locals {
  install = [for v in data.kubectl_file_documents.install.documents : {
    data : yamldecode(v)
    content : v
    }
  ]
  sync = [for v in data.kubectl_file_documents.sync.documents : {
    data : yamldecode(v)
    content : v
    }
  ]
}

resource "kubectl_manifest" "install" {
  for_each   = { for v in local.install : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [null_resource.flux_namespace]
  yaml_body  = each.value
}

resource "kubectl_manifest" "sync" {
  for_each   = { for v in local.sync : lower(join("/", compact([v.data.apiVersion, v.data.kind, lookup(v.data.metadata, "namespace", ""), v.data.metadata.name]))) => v.content }
  depends_on = [null_resource.flux_namespace]
  yaml_body  = each.value
}

resource "kubernetes_secret" "main" {
  depends_on = [kubectl_manifest.install]

  metadata {
    name      = data.flux_sync.main.secret
    namespace = data.flux_sync.main.namespace
  }

  data = {
    identity       = tls_private_key.main.private_key_pem
    "identity.pub" = tls_private_key.main.public_key_pem
    known_hosts    = local.known_hosts
  }
}

# GitHub
resource "github_repository" "main" {
  name       = var.repository_name
  visibility = var.repository_visibility
  auto_init  = true
}

resource "github_branch_default" "main" {
  repository = github_repository.main.name
  branch     = var.branch
}

resource "github_repository_deploy_key" "main" {
  title      = "aks"
  repository = github_repository.main.name
  key        = tls_private_key.main.public_key_openssh
  read_only  = true
}

resource "github_repository_file" "install" {
  repository = github_repository.main.name
  file       = data.flux_install.main.path
  content    = data.flux_install.main.content
  branch     = var.branch
}

resource "github_repository_file" "sync" {
  repository = github_repository.main.name
  file       = data.flux_sync.main.path
  content    = data.flux_sync.main.content
  branch     = var.branch
}

resource "github_repository_file" "kustomize" {
  repository = github_repository.main.name
  file       = data.flux_sync.main.kustomize_path
  content    = data.flux_sync.main.kustomize_content
  branch     = var.branch
}
