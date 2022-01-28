resource "kubernetes_namespace" "cert_manager" {
  provider = kubernetes.local
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
    value = "{--dns01-recursive-nameservers-only,--dns01-recursive-nameservers=ns1-09.azure-dns.com:53\\,ns2-09.azure-dns.net:53\\,ns3-09.azure-dns.org:53\\,ns4-09.azure-dns.info:53}"
  }
}

############################
# Certificates
############################

data "azurerm_key_vault" "this" {
  name                = "myVault-3721"
  resource_group_name = "myResourceGroup"
}
data "azurerm_key_vault_secret" "client_id" {
  name         = "sp-flux-istio"
  key_vault_id = data.azurerm_key_vault.this.id
}
data "azurerm_key_vault_secret" "client_secret" {
  name         = "sp-flux-istio-secret"
  key_vault_id = data.azurerm_key_vault.this.id
}
resource "kubernetes_secret" "secret" {
  provider = kubernetes.local
  metadata {
    name      = "cert-manager-dns-config-secret"
    namespace = kubernetes_namespace.cert_manager.id
  }
  data = {
    # Azure DNS client secret (for Azure DNS)
    CLIENT_SECRET = data.azurerm_key_vault_secret.client_secret.value
  }
}

data "template_file" "cert_manager_clusterissuer" {
  template = file("files/cert-manager-azure-clusterissuer.yaml.tmpl")
  vars = {
    email          = "glen.liu@cautiontape.ca"
    hostedZoneName = azurerm_dns_zone.azaks_dev.name
    # Azure DNS access credentials (for Azure DNS)
    clientID                = data.azurerm_key_vault_secret.client_id.value
    resourceGroupName       = azurerm_resource_group.rg.name
    resource_group_name_dns = azurerm_resource_group.rg.name
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
    dnsName                 = azurerm_dns_zone.azaks_dev.name
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
    dnsName                 = azurerm_dns_zone.azaks_dev.name
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
# resource "null_resource" "cert-manager-certificate-label" {
#   depends_on = [null_resource.cert-manager-certificate]

#   provisioner "local-exec" {
#     command = "kubectl wait --kubeconfig=${var.kubeconfig} --for=condition=ready -n cert-manager certificate/ingress-cert-${var.letsencrypt_environment} --timeout=10m && kubectl annotate --kubeconfig=${var.kubeconfig} secret ingress-cert-${var.letsencrypt_environment} -n cert-manager kubed.appscode.com/sync='app=kubed'"
#   }

#   provisioner "local-exec" {
#     when    = destroy
#     command = "kubectl annotate secret --kubeconfig=${var.kubeconfig} ingress-cert-${var.letsencrypt_environment} -n cert-manager kubed.appscode.com/sync-"
#   }
# }
