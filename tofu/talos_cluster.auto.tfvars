talos_cluster_config = {
  name = "talos"
  # This should point to the vip as below(if nodes on layer 2) or one of the nodes (if nodes not on layer 2)
  endpoint                     = "api.kube.pc-tips.se"
  vip                          = "10.25.150.10"
  gateway                      = "10.25.150.1"
  talos_machine_config_version = "v1.9.5"
  proxmox_cluster              = "host3"
  kubernetes_version           = "1.32.3"
  cilium = {
    bootstrap_manifest_path = "./inline-manifests/cilium-install.yaml"
    values_file_path        = "../k8s/infrastructure/network/cilium/values.yaml"
  }
  coredns = {
    bootstrap_manifest_path = "./inline-manifests/coredns-install.yaml"
    values_file_path        = "../k8s/infrastructure/network/coredns/values.yaml"
  }
  extra_manifests = [
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml",
    "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml"
  ]
  kubelet = <<-EOT
    clusterDNS:
      - 10.96.0.10
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
    extraArgs:
  EOT
  kernel = <<-EOT
    modules:
      - name: nvme_tcp
      - name: vfio_pci
  EOT
  api_server = <<-EOT
    extraArgs:
  EOT
  clusterName = "kube.pc-tips.se"
  network = {
    dnsDomain = "kube.pc-tips.se"
  }
}
