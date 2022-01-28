variable aks_cluster_name {
  type = string
}

variable kubeconfig_raw {
  type = string
  sensitive = true
}

variable flux_namespace {
  default = "flux-system"
}

variable "vault_name" {
  default = "myVault-3721"
  sensitive = true
}

variable "vault_rg_name" {
  default = "myResourceGroup"
  sensitive = true
}

variable "repository_name" {
  type        = string
  default     = "flux-demo"
  description = "github repository name"
}

variable "repository_visibility" {
  type        = string
  default     = "public"
  description = "How visible is the github repo"
}

variable "branch" {
  type        = string
  default     = "main"
  description = "branch name"
}

variable "target_path" {
  type        = string
  default     = "aks"
  description = "flux sync target path"
}
