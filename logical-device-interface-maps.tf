#############################
# Logical Devices + IF Maps #
#############################

locals {
  # Port roles shared across all port groups
  ld_port_roles = ["superspine", "spine", "leaf", "peer", "access", "generic"]

  # Logical device definitions: leaf, border, spine
  logical_devices = {
    leaf = {
      name    = "terraform_leaf"
      rows    = 2
      columns = 28
      port_groups = [
        { port_count = 48, port_speed = "10G" },
        { port_count = 8,  port_speed = "40G" },
      ]
    }
    border = {
      name    = "terraform_border"
      rows    = 2
      columns = 18
      port_groups = [
        { port_count = 36, port_speed = "40G" },
      ]
    }
    spine = {
      name    = "terraform_spine"
      rows    = 2
      columns = 16
      port_groups = [
        { port_count = 32, port_speed = "40G" },
      ]
    }
  }

  # Logical-to-physical interface mapping ranges per device type
  interface_map_ranges = {
    leaf = [
      {
        ld_panel       = 1
        ld_first_port  = 1
        phy_prefix     = "xe-0/0/"
        phy_first_port = 0
        count          = 48
      },
      {
        ld_panel       = 1
        ld_first_port  = 49
        phy_prefix     = "et-0/0/"
        phy_first_port = 48
        count          = 8
      },
    ]

    border = [
      {
        ld_panel       = 1
        ld_first_port  = 1
        phy_prefix     = "et-0/0/"
        phy_first_port = 0
        count          = 36
      },
    ]

    spine = [
      {
        ld_panel       = 1
        ld_first_port  = 1
        phy_prefix     = "et-0/0/"
        phy_first_port = 0
        count          = 32
      },
    ]
  }

  # Interface map definitions (name and device profile)
  interface_maps = {
    leaf = {
      name           = "im_leaf"
      device_profile = "Juniper_QFX5120-48Y_Junos"
    }
    border = {
      name           = "im_border"
      device_profile = "Juniper_QFX10002-36Q_Junos"
    }
    spine = {
      name           = "im_spine"
      device_profile = "Juniper_QFX5200-32C_Junos"
    }
  }

  # Build the flat interface list from the mapping ranges
  interfaces = {
    for k, ranges in local.interface_map_ranges :
    k => flatten([
      for map in ranges : [
        for i in range(map.count) : {
          logical_device_port     = format("%d/%d", map.ld_panel, map.ld_first_port + i)
          physical_interface_name = format("%s%d", map.phy_prefix, map.phy_first_port + i)
        }
      ]
    ])
  }
}

#####################
# Logical Devices   #
#####################

resource "apstra_logical_device" "ld" {
  for_each = local.logical_devices

  name = each.value.name

  panels = [
    {
      rows    = each.value.rows
      columns = each.value.columns
      port_groups = [
        for pg in each.value.port_groups : {
          port_count = pg.port_count
          port_speed = pg.port_speed
          port_roles = local.ld_port_roles
        }
      ]
    }
  ]
}

#####################
# Interface Maps    #
#####################

resource "apstra_interface_map" "im" {
  for_each = local.interface_maps

  name              = each.value.name
  logical_device_id = apstra_logical_device.ld[each.key].id
  device_profile_id = each.value.device_profile
  interfaces        = local.interfaces[each.key]
}
