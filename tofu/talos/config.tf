resource "talos_machine_secrets" "this" {
  talos_version = var.cluster.talos_machine_config_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.nodes : v.ip]
  endpoints            = [for k, v in var.nodes : v.ip if v.machine_type == "controlplane"]
}

locals {
  # Use GitOps-friendly approach to handle bootstrap manifests
  # Use `data.external` with fallback for Kustomize rendering
  cilium_bootstrap_manifests = [
    {
      name     = "cilium-bootstrap"
      contents = try(
        # Try to safely render the manifests with kustomize
        data.external.validated_cilium_kustomize.result.status == "success" ? data.external.validated_cilium_kustomize.result.manifest : null,
        # If that fails, fallback to reading the manifest file directly
        file("${path.root}/${var.cluster.cilium.bootstrap_manifest_path}")
      )
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

  coredns_bootstrap_manifests = [
    {
      name     = "coredns-bootstrap"
      contents = try(
        # Try to safely render the manifests with kustomize
        data.external.validated_coredns_kustomize.result.status == "success" ? data.external.validated_coredns_kustomize.result.manifest : null,
        # If that fails, fallback to reading the manifest file directly
        file("${path.root}/${var.cluster.coredns.bootstrap_manifest_path}")
      )
    },
    {
      name = "coredns-values"
      contents = yamlencode({
        apiVersion = "v1"
        kind       = "ConfigMap"
        metadata = {
          name      = "coredns-values"
          namespace = "kube-system"
        }
        data = {
          "values.yaml" = file("${path.root}/${var.cluster.coredns.values_file_path}")
        }
      })
    }
  ]

  # Combine all bootstrap manifests
  bootstrap_inline_manifests = concat(
    local.cilium_bootstrap_manifests,
    local.coredns_bootstrap_manifests
  )

  # Determine kustomize paths for rendering
  cilium_kustomize_dir = dirname("${path.root}/${var.cluster.cilium.bootstrap_manifest_path}")
  coredns_kustomize_dir = dirname("${path.root}/${var.cluster.coredns.bootstrap_manifest_path}")
}

# Safe external data sources for Kustomize rendering
# These use a count to make them optional and provide fallbacks
data "external" "cilium_kustomize_safe" {
  count = fileexists("${local.cilium_kustomize_dir}/kustomization.yaml") ? 1 : 0

  program = [
    "bash", "-c",
    <<-EOT
      set -eo pipefail

      # Check if kustomize exists, if not just output empty result
      if ! command -v kustomize &> /dev/null; then
        echo '{"manifest": ""}'
        exit 0
      fi

      # Try to build with kustomize, capture errors
      if output=$(kustomize build "${local.cilium_kustomize_dir}" 2>/dev/null); then
        # Success - return the manifest
        echo "{\"manifest\": $(echo "$output" | jq -sR .)}"
      else
        # Failure - return empty
        echo '{"manifest": ""}'
      fi
    EOT
  ]
}

data "external" "coredns_kustomize_safe" {
  count = fileexists("${local.coredns_kustomize_dir}/kustomization.yaml") ? 1 : 0

  program = [
    "bash", "-c",
    <<-EOT
      set -eo pipefail

      # Check if kustomize exists, if not just output empty result
      if ! command -v kustomize &> /dev/null; then
        echo '{"manifest": ""}'
        exit 0
      fi

      # Try to build with kustomize, capture errors
      if output=$(kustomize build "${local.coredns_kustomize_dir}" 2>/dev/null); then
        # Success - return the manifest
        echo "{\"manifest\": $(echo "$output" | jq -sR .)}"
      else
        # Failure - return empty
        echo '{"manifest": ""}'
      fi
    EOT
  ]
}

data "talos_machine_configuration" "this" {
  for_each         = var.nodes
  cluster_name     = var.cluster.name
  cluster_endpoint = "https://${var.cluster.endpoint}:6443"
  talos_version    = var.cluster.talos_machine_config_version != null ? var.cluster.talos_machine_config_version : (each.value.update == true ? var.image.update_version : var.image.version)
  machine_type     = each.value.machine_type
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  # Use a single common template for both worker and control plane nodes
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
      dns_domain   = var.cluster.dns_domain
      machine_type = each.value.machine_type
    }),
    # Only add controlplane specific configs for controlplane nodes
    each.value.machine_type == "controlplane" ? templatefile("${path.module}/machine-config/control-plane.yaml.tftpl", {
      kubelet         = var.cluster.kubelet
      api_server      = var.cluster.api_server
      extra_manifests = yamlencode(var.cluster.extra_manifests)
      inline_manifests = yamlencode(local.bootstrap_inline_manifests)
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

resource "terraform_data" "wait_for_talos" {
  depends_on = [talos_machine_configuration_apply.this]

  # This triggers the resource to be replaced if any machine config changes
  input = [for k, v in talos_machine_configuration_apply.this : v.machine_configuration_input]

  # Proper Terraform dependency management will handle the waiting
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [terraform_data.wait_for_talos]
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
