resource "apstra_datacenter_resource_pool_allocation" "vn-vni" {
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id
  role         = "vni_virtual_network_ids"
  pool_ids     = [apstra_vni_pool.terraform-vni.id]
}

variable "vns" {
  description = "Liste des Virtual Networks à créer"
  type = list(object({
    name                 = string
    vlan_id              = number
    vrf_name             = string
    ipv4_virtual_gateway = optional(string)
    ipv4_subnet          = optional(string)
    bindings             = list(string)
  }))
  default = []
}

locals {
  vn_leaf_labels = toset(flatten([
    for vn in var.vns : vn.bindings
  ]))
}

data "apstra_datacenter_systems" "leaves" {
  for_each     = local.vn_leaf_labels
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id

  filters = [{
    label = each.key
  }]

  # Must be read after device allocation so node labels are already set to friendly names
  depends_on = [apstra_datacenter_device_allocation.assign_devices]
}

data "apstra_datacenter_virtual_network_binding_constructor" "vn_bindings" {
  for_each    = { for vn in var.vns : vn.name => vn }
  
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id
  vlan_id = each.value.vlan_id

  switch_ids = [
    for leaf_label in each.value.bindings :
    one(data.apstra_datacenter_systems.leaves[leaf_label].ids)
  ]
}

resource "apstra_datacenter_virtual_network" "vns" {
  for_each = { for vn in var.vns : vn.name => vn }

  blueprint_id                 = apstra_datacenter_blueprint.terraform-pod1.id
  name                         = each.value.name
  type                         = "vxlan"
  ipv4_connectivity_enabled    = each.value.ipv4_subnet != null
  ipv4_virtual_gateway_enabled = each.value.ipv4_virtual_gateway != null

  routing_zone_id      = apstra_datacenter_routing_zone.vrfs[each.value.vrf_name].id
  ipv4_virtual_gateway = each.value.ipv4_virtual_gateway
  ipv4_subnet          = each.value.ipv4_subnet

  bindings = data.apstra_datacenter_virtual_network_binding_constructor.vn_bindings[each.key].bindings
}

# Auto-create a tagged connectivity template for each virtual network

resource "apstra_datacenter_connectivity_template_interface" "vn_ct" {
  for_each     = apstra_datacenter_virtual_network.vns
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id

  name        = "CT-${each.key}-TAGGED"
  description = "CT interface pour le VN ${each.key}"

  virtual_network_singles = {
    "vn" = {
      virtual_network_id = each.value.id
      tagged             = true
    }
  }

  tags = [
    "terraform",
    "vn:${each.key}",
  ]
}

