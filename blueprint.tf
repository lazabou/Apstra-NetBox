
# Instantiate a blueprint from the previously-created template
resource "apstra_datacenter_blueprint" "terraform-pod1" {
  name        = var.blueprint_name
  template_id = apstra_template_rack_based.terraform-template.id
  depends_on = [
    apstra_logical_device.ld,
    apstra_interface_map.im,
  ]
}


data "apstra_asn_pool" "details" {
  name       = var.asn_pool.name
  
  depends_on = [
    apstra_asn_pool.terraform-asn,
  ]
}

data "apstra_ipv4_pool" "lb" {
  name       = var.loopback_pool.name
  
    depends_on = [
    apstra_ipv4_pool.terraform-lb,
  ]
}

data "apstra_ipv4_pool" "link" {
  name       = var.link_pool.name
  
  depends_on = [
    apstra_ipv4_pool.terraform-link,
  ]
}



locals {
  # Apstra node names derived from rack type names — no need to hardcode them in tfvars
  apstra_node_names = {
    Spine1  = "spine1"
    Spine2  = "spine2"
    Border1 = "${replace(apstra_rack_type.terraform-border.name, "-", "_")}_001_leaf1"
    Border2 = "${replace(apstra_rack_type.terraform-border.name, "-", "_")}_001_leaf2"
    Leaf1   = "${replace(apstra_rack_type.terraform-compute.name, "-", "_")}_001_leaf1"
    Leaf2   = "${replace(apstra_rack_type.terraform-compute.name, "-", "_")}_001_leaf2"
  }

  asn_pools = {
    spine_asns = [data.apstra_asn_pool.details.id]
    leaf_asns  = [data.apstra_asn_pool.details.id]
  }
  ipv4_pools = {
    spine_loopback_ips  = [data.apstra_ipv4_pool.lb.id]
    leaf_loopback_ips   = [data.apstra_ipv4_pool.lb.id]
    spine_leaf_link_ips = [data.apstra_ipv4_pool.link.id]
  }
  switches = {
    Spine1 = {
      node_name        = local.apstra_node_names["Spine1"]
      device_key       = var.device_keys["Spine1"]
      interface_map_id = apstra_interface_map.im["spine"].id
    }
    Spine2 = {
      node_name        = local.apstra_node_names["Spine2"]
      device_key       = var.device_keys["Spine2"]
      interface_map_id = apstra_interface_map.im["spine"].id
    }
    Border1 = {
      node_name        = local.apstra_node_names["Border1"]
      device_key       = var.device_keys["Border1"]
      interface_map_id = apstra_interface_map.im["border"].id
    }
    Border2 = {
      node_name        = local.apstra_node_names["Border2"]
      device_key       = var.device_keys["Border2"]
      interface_map_id = apstra_interface_map.im["border"].id
    }
    Leaf1 = {
      node_name        = local.apstra_node_names["Leaf1"]
      device_key       = var.device_keys["Leaf1"]
      interface_map_id = apstra_interface_map.im["leaf"].id
    }
    Leaf2 = {
      node_name        = local.apstra_node_names["Leaf2"]
      device_key       = var.device_keys["Leaf2"]
      interface_map_id = apstra_interface_map.im["leaf"].id
    }
  }
}


resource "apstra_datacenter_device_allocation" "assign_devices" {
  for_each         = local.switches
  blueprint_id     = apstra_datacenter_blueprint.terraform-pod1.id
  node_name        = each.value.node_name

  # Assign the interface map to this node
  initial_interface_map_id = each.value.interface_map_id

  # Required to enable deployment
  system_attributes = {
    deploy_mode = "deploy"
    name        = var.nodes[each.key].label
    hostname    = var.nodes[each.key].hostname
  }

  device_key = each.value.device_key

  # Logical devices and interface maps must exist before device assignment
  depends_on = [
    apstra_logical_device.ld,
    apstra_interface_map.im,
  ]
}

# Assign ASN pools to fabric roles 
resource "apstra_datacenter_resource_pool_allocation" "asn" {
  for_each     = local.asn_pools
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id
  role         = each.key
  pool_ids     = each.value
}

# Assign IPv4 pools to fabric roles 
resource "apstra_datacenter_resource_pool_allocation" "ipv4" {
  for_each     = local.ipv4_pools
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id
  role         = each.key
  pool_ids     = each.value
}


resource "apstra_blueprint_deployment" "deploy" {
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id

  depends_on = [
    # VRFs
    apstra_datacenter_routing_zone.vrfs,
    apstra_datacenter_resource_pool_allocation.vrf_loopbacks,

    # VNs
    apstra_datacenter_virtual_network.vns,
    apstra_datacenter_resource_pool_allocation.vn-vni,

    # Generic systems and their CT assignments
    apstra_datacenter_generic_system.systems,
    apstra_datacenter_connectivity_templates_assignment.gs_assign,

    # Connectivity templates per virtual network
    apstra_datacenter_connectivity_template_interface.vn_ct,

    # Device allocation must be complete before deployment
    apstra_datacenter_device_allocation.assign_devices,

  ]

  comment = "Deployed by Terraform {{.TerraformVersion}}, Apstra provider {{.ProviderVersion}}, user $USER."
}