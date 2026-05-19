variable "loopback_pool" {
  type = object({
    name    = string
    network = string
  })
}

variable "link_pool" {
  type = object({
    name    = string
    network = string
  })
}

variable "asn_pool" {
  type = object({
    name  = string
    first = number
    last  = number
  })
}

variable "vni_pool" {
  type = object({
    name  = string
    first = number
    last  = number
  })
}

variable "device_keys" {
  type = map(string)
}

variable "blueprint_name" {
  type = string
}

variable "nodes" {
  description = "Node definitions: UI label and hostname"
  type = map(object({
    label    = string
    hostname = string
  }))
}

resource "apstra_ipv4_pool" "terraform-lb" {
  name    = var.loopback_pool.name
  subnets = [{ network = var.loopback_pool.network }]
}

resource "apstra_ipv4_pool" "terraform-link" {
  name    = var.link_pool.name
  subnets = [{ network = var.link_pool.network }]
}

resource "apstra_asn_pool" "terraform-asn" {
  name   = var.asn_pool.name
  ranges = [{ first = var.asn_pool.first, last = var.asn_pool.last }]
}

resource "apstra_vni_pool" "terraform-vni" {
  name   = var.vni_pool.name
  ranges = [{ first = var.vni_pool.first, last = var.vni_pool.last }]
}
