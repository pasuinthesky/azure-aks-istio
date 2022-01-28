variable rg_name {
  type = string
}

variable dns_zone {
  type = object({
    name = string
    name_servers = list(string)
  })
}

variable aks_cluster_name {
  type = string
}

variable kubeconfig_raw {
  type = string
  sensitive = true
}

variable "vault_name" {
  default = "myVault-3721"
  sensitive = true
}

variable "vault_rg_name" {
  default = "myResourceGroup"
  sensitive = true
}

variable sp_id_keyname {
  default = "sp-flux-istio"
  sensitive = true
}

variable sp_secret_keyname {
  default = "sp-flux-istio-secret"
  sensitive = true
}

variable letsencrypt_environment {
  default = "production"
}