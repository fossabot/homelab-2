resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.nodes

  node_name = each.value.host_node

  name        = each.key
  description = each.value.machine_type == "controlplane" ? "Talos Control Plane" : "Talos Worker"
  tags        = each.value.machine_type == "controlplane" ? ["k8s", "control-plane"] : ["k8s", "worker"]
  on_boot     = true
  vm_id       = each.value.vm_id

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu
    type  = "host"
  }

  memory {
    dedicated = each.value.ram_dedicated
  }

  network_device {
    bridge      = "vmbr0"
    vlan_id     = 150
    mac_address = each.value.mac_address
  }

  # Primary disk with proper size
  disk {
    datastore_id = lookup(each.value, "datastore_id", var.image.proxmox_datastore)
    interface    = "scsi0"
    size         = 32
    file_format  = "raw"
  }

  # Add additional disks if specified
  dynamic "disk" {
    for_each = lookup(each.value, "disks", {})
    content {
      datastore_id = lookup(each.value, "datastore_id", var.image.proxmox_datastore)
      interface    = "scsi${disk.key + 1}" # +1 because scsi0 is the boot disk
      size         = disk.value
      file_format  = "raw"
    }
  }

  # CD-ROM with Talos ISO
  cdrom {
    file_id = proxmox_virtual_environment_download_file.this[local.node_to_download_key[each.key]].id
  }

  boot_order = ["cdrom", "scsi0"]

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X.
  }

  initialization {
    datastore_id = lookup(each.value, "datastore_id", var.image.proxmox_datastore)

    # Optional DNS Block.  Update Nodes with a list value to use.
    dynamic "dns" {
      for_each = try(each.value.dns, null) != null ? { "enabled" = each.value.dns } : {}
      content {
        servers = each.value.dns
      }
    }

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.cluster.subnet_mask}"
        gateway = var.cluster.gateway
      }
    }
  }

  dynamic "hostpci" {
    for_each = lookup(each.value, "igpu", false) ? [1] : []
    content {
      # Passthrough iGPU
      device  = "hostpci0"
      mapping = "iGPU"
      pcie    = true
      rombar  = true
      xvga    = false
    }
  }
}
