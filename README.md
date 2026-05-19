# Terraform — NetBox to Apstra

This Terraform project automatically provisions an **Juniper Apstra** data center blueprint from data stored in **NetBox**. Instead of defining VRFs, VLANs, and server connectivity manually in `.tfvars` files, all network intent is sourced from NetBox via its REST API and translated into Apstra resources.

---

## Project Overview

```
NetBox (source of truth)
    │
    ├── VRFs          ──►  Apstra Routing Zones
    ├── VLANs         ──►  Apstra Virtual Networks + Connectivity Templates
    └── Servers       ──►  Apstra Generic Systems + CT Assignments
```

The project uses the **hashicorp/http** Terraform provider to call the NetBox REST API directly. NetBox integration is optional: if `netbox_token` is left empty, no NetBox data is fetched.

---

## Repository Structure

| File | Purpose |
|------|---------|
| `providers.tf` | Provider declarations (Apstra, HTTP) and NetBox connection variables |
| `netbox.tf` | All NetBox API calls and local data transformations |
| `vrf.tf` | Apstra routing zones sourced from NetBox VRFs |
| `virtual_networks.tf` | Apstra virtual networks sourced from NetBox VLANs |
| `generic-systems.tf` | Apstra generic systems sourced from NetBox servers |
| `blueprint.tf` | Blueprint creation and deployment |
| `resources.tf` | IP/ASN/VNI pool definitions |
| `racks.tf` | Rack type definitions |
| `logical-device-interface-maps.tf` | Logical device and interface map definitions |
| `template.tf` | Rack-based template |
| `netbox.secrets.tfvars` | NetBox URL and token (not committed) |
| `terraform.tfvars` | Blueprint name, node labels, pool ranges |

---

## NetBox Data Model

### VRFs — `ipam > VRFs`

Each VRF in NetBox becomes an **Apstra Routing Zone**.

| NetBox field | Usage in Apstra |
|---|---|
| `name` | Routing zone name |
| `custom_fields.l3vni` | L3 VNI assigned to the routing zone |

**Custom field required on VRFs:**

| Field | Type | Description |
|---|---|---|
| `l3vni` | Integer | EVPN L3 VNI for this VRF |

---

### VLANs — `ipam > VLANs`

Each VLAN in NetBox becomes an **Apstra Virtual Network** (type VXLAN).

| NetBox field | Usage in Apstra |
|---|---|
| `name` | Virtual network name |
| `vid` | VLAN ID bound to the virtual network |
| `custom_fields.vrf` | Routing zone (VRF) the virtual network belongs to |

The **L2 VNI** is not stored in NetBox — it is computed automatically:

```
L2VNI = VRF.l3vni + VLAN.vid
```

Example: VRF Blue (l3vni=100000) + vlan-100 (vid=100) → L2VNI = **100100**

The **leaf bindings** (which switches carry the virtual network) are derived automatically: Terraform looks at which servers have the VLAN in their `vlans` custom field, then resolves the leaf switches those servers are connected to via NetBox cable data.

**Custom field required on VLANs:**

| Field | Type | Description |
|---|---|---|
| `vrf` | Object → `ipam.vrf` | VRF (routing zone) this VLAN belongs to. **Required.** |

---

### Servers — `dcim > Devices` (role: server)

Each device with the role **server** becomes an **Apstra Generic System**.

Connectivity (links to leaf/border switches) is derived automatically from the cables recorded in NetBox — no manual wiring description is needed.

The **interface transform ID** is computed from the hardware model of the connected switch and the interface type:

| Switch model | Interface speed | Transform ID |
|---|---|---|
| QFX5120-48Y | 1G | 3 |
| QFX5120-48Y | 10G | 2 |
| QFX5120-48Y | 25G | 1 |
| QFX10002-36Q (ports 1,5,7,11,13,17,19,23,25,29,31,35) | 100G | 2 |
| QFX10002-36Q | 40G | 1 |
| QFX10002-36Q | 10G | 3 |
| Other models | 40G | 1 |
| Other models | 10G | 3 |

Speed is inferred from the NetBox interface **type** field (e.g. `10gbase-cu` → 10G). The `speed` field is not used.

**Custom fields required on Devices (role: server):**

| Field | Type | Description |
|---|---|---|
| `lag_mode` | Select | Apstra LAG mode for uplinks. Choices: `lacp_active`, `lacp_passive`, `static_lag`, `none`. Default: `lacp_active`. |
| `vlans` | Multi-object → `ipam.vlan` | VLANs this server is connected to. Used to derive VN bindings and CT assignments. |

---

## NetBox Custom Fields Summary

| Object type | Field name | Type | Purpose |
|---|---|---|---|
| `ipam.vrf` | `l3vni` | Integer | EVPN L3 VNI |
| `ipam.vlan` | `vrf` | Object → `ipam.vrf` | VRF ownership (required) |
| `dcim.device` | `lag_mode` | Select | Apstra LAG mode |
| `dcim.device` | `vlans` | Multi-object → `ipam.vlan` | VLAN membership |

---

## Variables

| Variable | File | Description |
|---|---|---|
| `apstra_url` | `netbox.secrets.tfvars` | Apstra controller URL (with credentials) |
| `netbox_url` | `netbox.secrets.tfvars` | NetBox base URL |
| `netbox_token` | `netbox.secrets.tfvars` | NetBox API token (sensitive) |
| `blueprint_name` | `terraform.tfvars` | Name of the Apstra blueprint |
| `nodes` | `terraform.tfvars` | Switch label and hostname mapping |
| `device_keys` | `terraform.tfvars` | Serial numbers for device allocation |
| `loopback_pool` | `terraform.tfvars` | Loopback IP pool name and prefix |
| `link_pool` | `terraform.tfvars` | Fabric link IP pool name and prefix |
| `asn_pool` | `terraform.tfvars` | ASN pool name and range |
| `vni_pool` | `terraform.tfvars` | VNI pool name and range |

---

## Usage

```bash
terraform init
terraform apply -var-file="netbox.secrets.tfvars"
```

To run without NetBox integration (manual mode), omit the `netbox_token` or leave it empty — VRFs, VLANs, and generic systems will not be created.

---

## How NetBox Data Flows into Apstra

```
NetBox API calls (data.http)
    │
    ├── /api/ipam/vrfs/          → local.netbox_vrfs
    │                                └─► apstra_datacenter_routing_zone
    │
    ├── /api/ipam/vlans/         → local.netbox_vlans
    │                                ├─► apstra_datacenter_virtual_network
    │                                └─► apstra_datacenter_connectivity_template_interface
    │
    ├── /api/dcim/devices/       → local._device_model_by_name
    │   (role=server)             → local.netbox_generic_systems
    │                                ├─► apstra_datacenter_generic_system
    │                                └─► apstra_datacenter_connectivity_templates_assignment
    │
    ├── /api/dcim/interfaces/    → local._ifaces_by_server
    │   (role=server)             → local._connected_switch_iface_ids
    │
    └── /api/dcim/interfaces/    → local._switch_iface_speed_by_key
        (connected switch side)   → local._switch_iface_transform_id
```
