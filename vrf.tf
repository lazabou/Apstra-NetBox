########################
#         VRFs         #
########################

resource "apstra_datacenter_resource_pool_allocation" "vrf-vni" {
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id
  role         = "evpn_l3_vnis"
  pool_ids     = [apstra_vni_pool.terraform-vni.id]
}

resource "apstra_datacenter_routing_zone" "vrfs" {
  for_each     = local.netbox_vrfs
  blueprint_id = apstra_datacenter_blueprint.terraform-pod1.id
  name         = each.key
  vni          = each.value
}

resource "apstra_datacenter_resource_pool_allocation" "vrf_loopbacks" {
  for_each = apstra_datacenter_routing_zone.vrfs

  blueprint_id    = apstra_datacenter_blueprint.terraform-pod1.id
  role            = "leaf_loopback_ips"
  pool_ids        = [apstra_ipv4_pool.terraform-lb.id]
  routing_zone_id = each.value.id
}
