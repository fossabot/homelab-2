resource "talos_machine_secrets" "this" {
  talos_version = var.cluster.talos_machine_config_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.nodes : v.ip]
  endpoints            = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
}

# External data source to run Kustomize for Cilium
data "external" "cilium_kustomize" {
  program = [
    "bash", "-c",
    "set -euo pipefail; out=$(kustomize build --enable-helm \"${path.root}/../k8s/infrastructure/network/cilium\" | jq -Rs .); echo \"{\\\"manifest\\\": $out}\""
  ]
}




resource "local_file" "cilium_rendered_manifest" {
  content  = data.external.cilium_kustomize.result["manifest"]
  filename = "${path.module}/rendered/cilium-manifest.yaml"
}

resource "terraform_data" "cilium_bootstrap_inline_manifests" {
  input = [
    {
      name     = "cilium-bootstrap"
      contents = local_file.cilium_rendered_manifest.content
    },
    {
      name = "cilium-values"
      contents = yamlencode({
        apiVersion = "v1"
        kind       = "ConfigMap"
        metadata = {
          name      = "cilium-values"
          namespace = "kube-system"
        }
        data = {
          "values.yaml" = file("${path.root}/${var.cluster.cilium.values_file_path}")
        }
      })
    }
  ]
}
# External data source to run Kustomize for CoreDNS
data "external" "coredns_kustomize" {
  program = [
    "bash", "-c",
    "set -euo pipefail; out=$(kustomize build --enable-helm \"${path.root}/../k8s/infrastructure/network/coredns\" | jq -Rs .); echo \"{\\\"manifest\\\": $out}\""
  ]
}




resource "local_file" "coredns_rendered_manifest" {
  content  = data.external.coredns_kustomize.result["manifest"]
  filename = "${path.module}/rendered/coredns-manifest.yaml"
}

resource "terraform_data" "coredns_bootstrap_inline_manifests" {
  input = [
    {
      name     = "coredns-bootstrap"
      contents = local_file.coredns_rendered_manifest.content
    },
    {
      name = "coredns-values"
      contents = yamlencode({
        metadata = {
          namespace = "kube-system"
        }
        data = {
          "values.yaml" = file("${path.root}/${var.cluster.coredns.values_file_path}")
        }
      })
    }
  ]
}

data "talos_machine_configuration" "this" {
  for_each         = var.nodes
  cluster_name     = var.cluster.name
  cluster_endpoint = "https://${var.cluster.endpoint}:6443"
  talos_version    = var.cluster.talos_machine_config_version != null ? var.cluster.talos_machine_config_version : (each.value.update == true ? var.image.update_version : var.image.version)
  machine_type     = each.value.machine_type
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  config_patches = compact([
    templatefile("${path.module}/machine-config/common.yaml.tftpl", {
      node_name    = each.value.host_node
      cluster_name = var.cluster.proxmox_cluster
      hostname     = each.key
      ip           = each.value.ip
      mac_address  = lower(each.value.mac_address)
      gateway      = var.cluster.gateway
      subnet_mask  = var.cluster.subnet_mask
      vip          = each.value.machine_type == "controlplane" ? var.cluster.vip : null
    }),
    each.value.machine_type == "controlplane" ? templatefile("${path.module}/machine-config/control-plane.yaml.tftpl", {
      kubelet         = var.cluster.kubelet
      api_server      = var.cluster.api_server
      extra_manifests = yamlencode(var.cluster.extra_manifests)
      inline_manifests = yamlencode(concat(
        terraform_data.cilium_bootstrap_inline_manifests.input,
        terraform_data.coredns_bootstrap_inline_manifests.input
      ))
    }) : null

  ])
}


resource "talos_machine_configuration_apply" "this" {
  depends_on                  = [proxmox_virtual_environment_vm.this]
  for_each                    = var.nodes
  node                        = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration

  lifecycle {
    replace_triggered_by = [proxmox_virtual_environment_vm.this[each.key]]
  }
}
resource "null_resource" "wait_for_talos" {
  depends_on = [talos_machine_configuration_apply.this]

  provisioner "local-exec" {
    command = "sleep 10"
  }
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]
  node                 = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"][0]
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this
  ]
  client_configuration = data.talos_client_configuration.this.client_configuration
  control_plane_nodes  = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
  worker_nodes         = [for k, v in var.nodes : v.ip if v.machine_type == "worker"]
  endpoints            = data.talos_client_configuration.this.endpoints
  timeouts = {
    read = "10m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this,
    data.talos_cluster_health.this
  ]
  node                 = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"][0]
  client_configuration = talos_machine_secrets.this.client_configuration
  timeouts = {
    read = "1m"
  }
}
