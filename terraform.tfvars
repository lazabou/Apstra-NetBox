blueprint_name = "Demo-DC"

nodes = {
  Spine1  = { label = "Spine1",  hostname = "Spine1"  }
  Spine2  = { label = "Spine2",  hostname = "Spine2"  }
  Border1 = { label = "Border1", hostname = "Border1" }
  Border2 = { label = "Border2", hostname = "Border2" }
  Leaf1   = { label = "Leaf1",   hostname = "Leaf1"   }
  Leaf2   = { label = "Leaf2",   hostname = "Leaf2"   }
}

device_keys = {
  Spine1  = "WH0216290096"
  Spine2  = "WH0217430051"
  Border1 = "DA722"
  Border2 = "DL440"
  Leaf1   = "XH3722180714"
  Leaf2   = "XH3722180698"
}

loopback_pool = { name = "Terraform-Loopback", network = "10.0.0.0/24" }

link_pool = { name = "Terraform-Link", network = "10.1.0.0/24" }

asn_pool = { name = "Terraform-ASN", first = 65100, last = 65199 }

vni_pool = { name = "Terraform-vni", first = 10000, last = 19999 }
