terraform {
  required_version = ">=1.1.3"
}

module aks {
  source = "./modules/aks"
}

module istio {
  source = "./modules/istio"
  aks_cluster_name  = module.aks.cluster_name
  kubeconfig_raw    = module.aks.kubeconfig_raw
  deploy_sample_app = true
}

module flux {
  source = "./modules/flux"
  aks_cluster_name = module.aks.cluster_name
  kubeconfig_raw   = module.aks.kubeconfig_raw
}

module flagger {
  source = "./modules/flagger"
  aks_cluster_name = module.aks.cluster_name
  kubeconfig_raw   = module.aks.kubeconfig_raw
  prometheus_url   = module.istio.prometheus_url
  istio_namespace  = module.istio.istio_namespace
}

module certmgr {
  source = "./modules/cert-manager"
  aks_cluster_name = module.aks.cluster_name
  kubeconfig_raw   = module.aks.kubeconfig_raw
  rg_name          = module.aks.rg_name
  dns_zone         = module.aks.dns_zone
}
# output test {
#   value = module.aks.cluster_name
# }

# output test1 {
#   value = module.aks.dns_zone
# }

# output test2 {
#   value = trimsuffix("%{ for i in module.aks.dns_zone.name_servers }${trimsuffix(i, ".")}:53,%{ endfor }", ",")
# }

# output test3 {
#   value = yamldecode(module.aks.kubeconfig_raw)
#   sensitive = true
# }

# output test4 {
#   value = jsondecode(module.aks.test)
# }

# output test6 {
#   value = module.istio.istio_ing_gw
# }

# output test7 {
#   value = module.istio.prometheus
# }

# output test8 {
#   value = module.istio.prometheus_url
# }