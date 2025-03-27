talos_image = {
  version = "v1.9.5"
  update_version = "v1.9.5" # renovate: github-releases=siderolabs/talos
  schematic_path = "talos/image/schematic.yaml"
  # Point this to a new schematic file to update the schematic
  # update_schematic_path = "image/schematic.yaml"

  # List of Proxmox datastores that use ZFS storage
  # These will use raw.gz format with appropriate decompression
  zfs_datastores = ["rpool3"]
}
