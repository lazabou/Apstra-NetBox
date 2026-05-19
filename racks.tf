resource "apstra_rack_type" "terraform-compute" {
  name                       = "terraform-compute"
  fabric_connectivity_design = "l3clos"

  leaf_switches = {
    leaf = {
      logical_device_id   = apstra_logical_device.ld["leaf"].id
      spine_link_count    = 1
      spine_link_speed    = "40G"
      redundancy_protocol = "esi"
    }
  }
}

resource "apstra_rack_type" "terraform-border" {
  name                       = "terraform-border"
  fabric_connectivity_design = "l3clos"

  leaf_switches = {
    leaf = {
      logical_device_id   = apstra_logical_device.ld["border"].id
      spine_link_count    = 1
      spine_link_speed    = "40G"
      redundancy_protocol = "esi"
    }
  }
}
