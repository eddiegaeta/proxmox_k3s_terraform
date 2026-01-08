terraform {
  required_version = ">= 1.0"
  
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.68"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_api_url
  username = var.proxmox_api_user
  password = var.proxmox_api_password
  insecure = var.proxmox_insecure
  
  ssh {
    agent    = true
    username = var.proxmox_ssh_user
  }
}
