terraform {
  required_providers {
    apstra = {
      source  = "Juniper/apstra"
      version = "0.101.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

variable "apstra_url" {
  type = string
}

provider "apstra" {
  url                     = var.apstra_url
  tls_validation_disabled = true
  blueprint_mutex_enabled = false
  experimental            = true
}

variable "netbox_url" {
  type    = string
  default = ""
}

variable "netbox_token" {
  type      = string
  sensitive = true
  default   = ""
}
