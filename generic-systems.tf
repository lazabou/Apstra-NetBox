############################
#          Locals          #
############################

locals {
  gs_by_name = local.netbox_generic_systems

  gs_leaf_labels = toset(flatten([
    for gs in local.netbox_generic_systems : [
      for l in gs.links : l.leaf_label
    ]
  ]))
}

############################
#  Target leaf switches    #
############################

data "apstra_datacenter_systems" "gs_leaves" {
  for_each     = local.gs_leaf_labels
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id

  filters = [{
    label = each.key
  }]

  # Must be read after device allocation so node labels are already set to friendly names
  depends_on = [apstra_datacenter_device_allocation.assign_devices]
}

############################
#     Generic Systems      #
############################

resource "apstra_datacenter_generic_system" "systems" {
  for_each = local.gs_by_name

  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id
  name         = each.value.name
  hostname     = each.value.hostname
  tags         = null

  depends_on = [
    apstra_logical_device.ld,
    apstra_interface_map.im,
    apstra_datacenter_device_allocation.assign_devices,
  ]

  links = [
    for l in each.value.links : {
      tags                          = each.value.link_tags
      lag_mode                      = l.lag_mode
      target_switch_id              = one(data.apstra_datacenter_systems.gs_leaves[l.leaf_label].ids)
      target_switch_if_name         = l.target_switch_if_name
      target_switch_if_transform_id = l.target_switch_if_transform_id
      group_label                   = l.group_label
    }
  ]
}

############################
#  GS interfaces (APs)     #
############################

data "apstra_datacenter_interfaces_by_link_tag" "gs" {
  for_each     = local.gs_by_name
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id

  tags = each.value.link_tags

  depends_on = [
    apstra_datacenter_generic_system.systems,
  ]
}

############################
#  Assign VN CTs to GS     #
############################

resource "apstra_datacenter_connectivity_templates_assignment" "gs_assign" {
  for_each     = { for k, v in local.gs_by_name : k => v if length(v.vlan_names) > 0 }
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id

  application_point_id = one(
    data.apstra_datacenter_interfaces_by_link_tag.gs[each.key].ids
  )

  connectivity_template_ids = [
    for vlan_name in each.value.vlan_names :
    apstra_datacenter_connectivity_template_interface.vn_ct[vlan_name].id
  ]

  depends_on = [
    data.apstra_datacenter_interfaces_by_link_tag.gs,
    apstra_datacenter_connectivity_template_interface.vn_ct,
  ]
}
