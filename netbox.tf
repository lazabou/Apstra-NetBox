########################
#  NetBox — VRFs       #
########################
# NetBox is enabled only when a token is provided.

locals {
  netbox_enabled = var.netbox_token != "" # true when a NetBox token is supplied
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

  # Map: VRF name -> L3VNI (from custom field); null if not set
  netbox_vrfs = nonsensitive({
    for vrf in local._vrf_results :
    vrf.name => try(vrf.custom_fields["l3vni"], null)
  })
}

########################
# NetBox — VLANs       #
########################

data "http" "netbox_vlans" {
  count = local.netbox_enabled ? 1 : 0
  url   = "${var.netbox_url}/api/ipam/vlans/?format=json&limit=0"

  request_headers = {
    Authorization = "Token ${var.netbox_token}"
    Accept        = "application/json"
  }
}

locals {
  _vlan_results = try(jsondecode(data.http.netbox_vlans[0].response_body).results, [])

  netbox_vlans = nonsensitive({
    for vlan in local._vlan_results :
    vlan.name => {
      name     = vlan.name
      vlan_id  = vlan.vid
      vrf_name = vlan.custom_fields.vrf.name
      vni      = local.netbox_vrfs[vlan.custom_fields.vrf.name] + vlan.vid

      # Bindings: leaf switches connected to servers that carry this VLAN
      bindings = toset(flatten([
        for srv in local._server_results : [
          for iface in local._ifaces_by_server[srv.name] :
          iface.leaf_label
          if contains(
            srv.custom_fields["vlans"] != null ? [for v in srv.custom_fields["vlans"] : v.name] : [],
            vlan.name
          )
        ]
      ]))
    }
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
  _server_results       = try(jsondecode(data.http.netbox_servers[0].response_body).results, [])
  _server_iface_results = try(jsondecode(data.http.netbox_server_interfaces[0].response_body).results, [])

  # IDs of the switch-side connected interfaces (non-sensitive — just DB integers)
  _connected_switch_iface_ids = nonsensitive(distinct(flatten([
    for iface in local._server_iface_results :
    iface.connected_endpoints != null ? [for ep in iface.connected_endpoints : tostring(ep.id)] : []
  ])))

  # Server interfaces grouped by device name, keeping only those connected to a switch
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
}

data "http" "netbox_devices" {
  count = local.netbox_enabled ? 1 : 0
  url   = "${var.netbox_url}/api/dcim/devices/?format=json&limit=0"

  request_headers = {
    Authorization = "Token ${var.netbox_token}"
    Accept        = "application/json"
  }
}

data "http" "netbox_switch_ifaces" {
  count = local.netbox_enabled && length(local._connected_switch_iface_ids) > 0 ? 1 : 0
  url   = "${var.netbox_url}/api/dcim/interfaces/?format=json&limit=0&${join("&", formatlist("id=%s", local._connected_switch_iface_ids))}"

  request_headers = {
    Authorization = "Token ${var.netbox_token}"
    Accept        = "application/json"
  }
}

locals {
  _all_device_results   = try(jsondecode(data.http.netbox_devices[0].response_body).results, [])
  _switch_iface_results = try(jsondecode(data.http.netbox_switch_ifaces[0].response_body).results, [])

  # Map: device name -> hardware model
  _device_model_by_name = nonsensitive({
    for d in local._all_device_results : d.name => d.device_type.model
  })

  # NetBox interface type -> speed category
  _iface_type_to_speed = {
    "100gbase-x-qsfp28"  = "100G"
    "100gbase-x-cfp"     = "100G"
    "100gbase-x-cfp2"    = "100G"
    "100gbase-cr4"       = "100G"
    "100gbase-sr4"       = "100G"
    "100gbase-lr4"       = "100G"
    "40gbase-x-qsfpp"    = "40G"
    "40gbase-x-qsfp"     = "40G"
    "40gbase-sr4-bd"     = "40G"
    "40gbase-kr4"        = "40G"
    "40gbase-cr4"        = "40G"
    "25gbase-x-sfp28"    = "25G"
    "10gbase-x-sfpp"     = "10G"
    "10gbase-x-sfp"      = "10G"
    "10gbase-cx4"        = "10G"
    "10gbase-t"          = "10G"
    "10gbase-cu"         = "10G"
    "1000base-t"         = "1G"
    "1000base-x-sfp"     = "1G"
  }

  # Map: "DeviceName/IfaceName" -> speed category (e.g. "10G", "40G")
  _switch_iface_speed_by_key = nonsensitive({
    for iface in local._switch_iface_results :
    "${iface.device.name}/${iface.name}" => try(local._iface_type_to_speed[iface.type.value], null)
  })

  # QFX10002-36Q ports that support 100G (transform_id=2)
  _qfx10002_100g_ports = toset([1, 5, 7, 11, 13, 17, 19, 23, 25, 29, 31, 35])

  # Pre-computed transform_id for each connected switch interface.
  # Key format: "DeviceName/iface-X/Y/Z" — port number is the last "/" segment.
  _switch_iface_transform_id = nonsensitive({
    for key, speed in local._switch_iface_speed_by_key :
    key => (
      # QFX5120-48Y: 1G→3, 10G→2, 25G→1
      try(local._device_model_by_name[split("/", key)[0]], "") == "QFX5120-48Y" ?
        try({ "1G" = 3, "10G" = 2, "25G" = 1 }[coalesce(speed, "")], 2) :

      # QFX10002-36Q: 100G allowed only on listed ports
      try(local._device_model_by_name[split("/", key)[0]], "") == "QFX10002-36Q" ?
        (
          speed == "100G" && try(
            contains(local._qfx10002_100g_ports, tonumber(element(split("/", key), length(split("/", key)) - 1))),
            false
          ) ? 2 :
          try({ "10G" = 3, "40G" = 1 }[coalesce(speed, "")], 1)
        ) :

      # Default (other models): 40G→1, 10G→3
      try({ "10G" = 3, "40G" = 1 }[coalesce(speed, "")], 1)
    )
  })

  # Map: server name -> generic system object ready for Apstra
  netbox_generic_systems = nonsensitive({
    for srv in local._server_results :
    srv.name => {
      name       = srv.name
      hostname   = srv.name
      lag_mode   = try(srv.custom_fields["lag_mode"], "lacp_active")
      link_tags  = [srv.name]
      vlan_names = srv.custom_fields["vlans"] != null ? [for v in srv.custom_fields["vlans"] : v.name] : []
      links = [
        for iface in local._ifaces_by_server[srv.name] : {
          leaf_label            = iface.leaf_label
          target_switch_if_name = iface.target_switch_if_name
          group_label           = srv.name
          lag_mode              = try(srv.custom_fields["lag_mode"], "lacp_active")
          target_switch_if_transform_id = try(
            local._switch_iface_transform_id["${iface.leaf_label}/${iface.target_switch_if_name}"],
            2
          )
        }
      ]
    }
  })
}
