provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "this" {
  name     = "aks-resource-group"
  location = var.location
}

resource "azurerm_virtual_network" "this" {
  name                = "aks-vnet"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = ["192.168.0.0/16"]
}

resource "azurerm_subnet" "this" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["192.168.1.0/24"]
  service_endpoints    = ["Microsoft.ContainerRegistry"]
}

resource "azurerm_dns_zone" "this" {
  name                = var.dns_zone
  resource_group_name = azurerm_resource_group.this.name
}

# uncomment this part if you have an AAD group that you want to use it for admin tasks of the cluster
#
# resource "azuread_group" "aks-admin-group" {
#   display_name     = "AKS-admins"
#   security_enabled = true
# }

# resource "azurerm_log_analytics_workspace" "this" {
#   name                = "azaks-dev"
#   location            = azurerm_resource_group.this.location
#   resource_group_name = azurerm_resource_group.this.name
#   sku                 = "Free"
#   retention_in_days   = 30
# }

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.worker_node_dns_prefix
  default_node_pool {
    name                  = "default"
    vnet_subnet_id        = azurerm_subnet.this.id
    type                  = "VirtualMachineScaleSets"
    availability_zones    = ["1", "2", "3"]
    enable_auto_scaling   = true
    enable_node_public_ip = false
    max_count             = 3
    min_count             = 1
    os_disk_size_gb       = 80
    os_disk_type          = "Ephemeral"
    vm_size               = "Standard_DS2_v2"
  }
  role_based_access_control {
    enabled = true
    azure_active_directory {
      managed = true
      # uncomment this part if you defined AAD group for admin above
      # admin_group_object_ids = [azuread_group.aks-admin-group.id]
    }
  }
  identity {
    type = "SystemAssigned"
  }
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "Standard"
  }

  addon_profile {
    aci_connector_linux {
      enabled = false
    }

    azure_policy {
      enabled = true
    }

    http_application_routing {
      enabled = false
    }

    # oms_agent {
    #   enabled                    = true
    #   log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
    # }
  }
}

# resource "local_file" "kube_config" {
#   content  = azurerm_kubernetes_cluster.this.kube_admin_config_raw
#   filename = ".kube/${azurerm_kubernetes_cluster.this.name}"
# }
