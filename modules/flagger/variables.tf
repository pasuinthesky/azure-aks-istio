variable istio_namespace {
  type = string
}

variable prometheus_url {
  type = string
}

variable aks_cluster_name {
  type = string
}

variable kubeconfig_raw {
  type = string
  sensitive = true
}