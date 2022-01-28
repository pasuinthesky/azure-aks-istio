variable deploy_sample_app {
  default = false
}

variable istio_namespace {
  default = "istio-system"
}

variable istio_ingress_gateway {
  default = "istio-ingressgateway"
}

variable sample_app_path {
  default = "samples/bookinfo/*.yaml"
}

variable aks_cluster_name {
  type = string
}

variable kubeconfig_raw {
  type = string
  sensitive = true
}
