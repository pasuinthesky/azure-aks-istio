output cluster_name {
  value = azurerm_kubernetes_cluster.this.name
}

output kubeconfig_raw {
  value = azurerm_kubernetes_cluster.this.kube_admin_config_raw
  sensitive = true
}

output rg_name {
  value = azurerm_resource_group.this.name
}

output dns_zone {
  value = {
    name = var.dns_zone, 
    name_servers = azurerm_dns_zone.this.name_servers
  }
}
# output test {
#     value = tostring(jsonencode(azurerm_kubernetes_cluster.this.kube_admin_config.0))
# }