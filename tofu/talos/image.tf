locals {
  version = var.image.version
  schematic = file("${path.module}/${var.image.schematic_path}")
  schematic_id = jsondecode(data.http.schematic_id.response_body)["id"]
  update_version = coalesce(var.image.update_version, var.image.version)
  update_schematic_path = coalesce(var.image.update_schematic_path, var.image.schematic_path)
  update_schematic = file("${path.module}/${local.update_schematic_path}")
  update_schematic_id = jsondecode(data.http.updated_schematic_id.response_body)["id"]
  image_id = "${local.schematic_id}_${local.version}"
  update_image_id = "${local.update_schematic_id}_${local.update_version}"

  # Node configurations with version info - per node
  node_configurations = {
    for k, v in var.nodes :
    k => {
      host_node = v.host_node
      datastore_id = lookup(v, "datastore_id", var.image.proxmox_datastore)
      version = v.update == true ? local.update_version : local.version
      schematic_id = v.update == true ? local.update_schematic_id : local.schematic_id
      image_id = v.update == true ? local.update_image_id : local.image_id
    }
  }

  # Create a properly deduplicated map for downloads
  # Key includes datastore_id to handle different storage pools correctly
  download_entries = [
    for k, v in local.node_configurations : {
      key = "${v.host_node}_${v.datastore_id}_${v.image_id}"
      value = {
        host_node = v.host_node
        datastore_id = v.datastore_id
        version = v.version
        schematic_id = v.schematic_id
        image_id = v.image_id
      }
    }
  ]

  # Use distinct to eliminate duplicate downloads
  unique_downloads = {
    for entry in distinct(local.download_entries) : entry.key => entry.value
  }

  # Create a lookup map to find the right download for each VM
  node_to_download_key = {
    for k, v in local.node_configurations :
    k => "${v.host_node}_${v.datastore_id}_${v.image_id}"
  }
}

data "http" "schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.schematic
}

data "http" "updated_schematic_id" {
  url          = "${var.image.factory_url}/schematics"
  method       = "POST"
  request_body = local.update_schematic
}

# Download Talos images - one per unique combination of host_node, datastore_id, and image_id
resource "proxmox_virtual_environment_download_file" "this" {
  for_each = local.unique_downloads

  node_name    = each.value.host_node
  content_type = "iso"
  datastore_id = each.value.datastore_id
  file_name    = "talos-${each.value.schematic_id}-${each.value.version}-${var.image.platform}-${var.image.arch}.iso"
  url          = "${var.image.factory_url}/image/${each.value.schematic_id}/${each.value.version}/${var.image.platform}-${var.image.arch}.iso"
  overwrite    = false
}


