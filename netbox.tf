########################
#  NetBox — VRFs       #
########################

locals {
  netbox_enabled = var.netbox_token != ""
}

data "http" "netbox_vrfs" {
  count = local.netbox_enabled ? 1 : 0
  url   = "${var.netbox_url}/api/ipam/vrfs/?format=json&limit=0"

  request_headers = {
    Authorization = "Token ${var.netbox_token}"
    Accept        = "application/json"
  }
}

locals {
  _vrf_results = local.netbox_enabled ? jsondecode(
    data.http.netbox_vrfs[0].response_body
  ).results : []

  netbox_vrfs = nonsensitive({
    for vrf in local._vrf_results :
    vrf.name => try(vrf.custom_fields["l3vni"], null)
  })
}

########################
# NetBox — Servers     #
########################

data "http" "netbox_servers" {
  count = local.netbox_enabled ? 1 : 0
  url   = "${var.netbox_url}/api/dcim/devices/?role=server&format=json&limit=0"

  request_headers = {
    Authorization = "Token ${var.netbox_token}"
    Accept        = "application/json"
  }
}

data "http" "netbox_server_interfaces" {
  count = local.netbox_enabled ? 1 : 0
  url   = "${var.netbox_url}/api/dcim/interfaces/?role=server&format=json&limit=0"

  request_headers = {
    Authorization = "Token ${var.netbox_token}"
    Accept        = "application/json"
  }
}

locals {
  _server_results = local.netbox_enabled ? jsondecode(
    data.http.netbox_servers[0].response_body
  ).results : []

  _server_iface_results = local.netbox_enabled ? jsondecode(
    data.http.netbox_server_interfaces[0].response_body
  ).results : []

  # Interfaces groupées par nom de device, filtrées sur celles connectées à un leaf
  _ifaces_by_server = {
    for srv in local._server_results :
    srv.name => [
      for iface in local._server_iface_results :
      {
        leaf_label            = iface.connected_endpoints[0].device.name
        target_switch_if_name = iface.connected_endpoints[0].name
      }
      if iface.device.id == srv.id && length(iface.connected_endpoints) > 0
    ]
  }

  # Map name -> objet generic system prêt pour Apstra
  netbox_generic_systems = nonsensitive({
    for srv in local._server_results :
    srv.name => {
      name      = srv.name
      hostname  = srv.name
      lag_mode  = try(srv.custom_fields["lag_mode"], "lacp_active")
      link_tags = [srv.name]
      links = [
        for iface in local._ifaces_by_server[srv.name] : {
          leaf_label                    = iface.leaf_label
          target_switch_if_name         = iface.target_switch_if_name
          target_switch_if_transform_id = 2
          group_label                   = srv.name
          lag_mode                      = try(srv.custom_fields["lag_mode"], "lacp_active")
        }
      ]
    }
  })
}
