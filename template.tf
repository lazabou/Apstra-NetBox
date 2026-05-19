
resource "apstra_template_rack_based" "terraform-template" {
  name                     = "Terraform-template"
  asn_allocation_scheme    = "unique"
  overlay_control_protocol = "evpn"
  spine = {
    count             = 2
    logical_device_id   = apstra_logical_device.ld["spine"].id
  }
  rack_infos = {
    (apstra_rack_type.terraform-compute.id)    = { count = 1 }
    (apstra_rack_type.terraform-border.id) = { count = 1 }
  }
}