talos_nodes = {
  "ctrl-00" = {
    host_node     = "host3"
    machine_type  = "controlplane"
    ip            = "10.25.150.11"
    mac_address   = "bc:24:11:e6:ba:07"
    vm_id         = 8101
    cpu           = 4
    ram_dedicated = 4096
    update        = false
    igpu          = false
  }
  "ctrl-01" = {
    host_node     = "host3"
    machine_type  = "controlplane"
    ip            = "10.25.150.12"
    mac_address   = "bc:24:11:44:94:5c"
    vm_id         = 8102
    cpu           = 4
    ram_dedicated = 4096
    update        = false
    igpu          = false
  }
  "ctrl-02" = {
    host_node     = "host3"
    machine_type  = "controlplane"
    ip            = "10.25.150.13"
    mac_address   = "bc:24:11:1e:1d:2f"
    vm_id         = 8103
    cpu           = 4
    ram_dedicated = 4096
    update        = false
  }
  "work-00" = {
    host_node     = "host3"
    machine_type  = "worker"
    ip            = "10.25.150.21"
    mac_address   = "bc:24:11:64:5b:cb"
    vm_id         = 8201
    cpu           = 4
    ram_dedicated = 3096
    update        = false
    disks = {
      longhorn = "scsi:100G"
    }
  }
  "work-01" = {
    host_node     = "host3"
    machine_type  = "worker"
    ip            = "10.25.150.22"
    mac_address   = "bc:24:11:c9:22:c3"
    vm_id         = 8202
    cpu           = 4
    ram_dedicated = 4096
    update        = false
    disks = {
      longhorn = "scsi:100G"
    }
  }
  "work-02" = {
    host_node     = "host3"
    machine_type  = "worker"
    ip            = "10.25.150.23"
    mac_address   = "bc:24:11:6f:20:03"
    vm_id         = 8203
    cpu           = 4
    ram_dedicated = 4096
    update        = false
    disks = {
      longhorn = "scsi:100G"
    }
  }
}
