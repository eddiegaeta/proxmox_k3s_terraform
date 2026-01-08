variable "proxmox_api_url" {
  description = "Proxmox API URL (e.g., https://proxmox.local:8006)"
  type        = string
}

variable "proxmox_api_user" {
  description = "Proxmox API user (e.g., root@pam)"
  type        = string
  default     = "root@pam"
}

variable "proxmox_api_password" {
  description = "Proxmox API password"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH user for Proxmox host"
  type        = string
  default     = "root"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "proxmox"
}

variable "storage_pool" {
  description = "Storage pool for LXC container disks (e.g., local-lvm, truenas)"
  type        = string
  default     = "local-lvm"
}

variable "template_storage" {
  description = "Storage pool for templates and ISOs"
  type        = string
  default     = "local"
}

variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "Network gateway"
  type        = string
  default     = "192.168.86.1"
}

variable "nameserver" {
  description = "DNS nameserver"
  type        = string
  default     = "8.8.8.8"
}

variable "ssh_public_key" {
  description = "SSH public key for root access"
  type        = string
}

variable "root_password" {
  description = "Root password for LXC containers"
  type        = string
  sensitive   = true
}

# k3s Control Plane
variable "k3s_controller_vmid" {
  description = "VMID for k3s controller"
  type        = number
  default     = 110
}

variable "k3s_controller_hostname" {
  description = "Hostname for k3s controller"
  type        = string
  default     = "k3s-c01"
}

variable "k3s_controller_ip" {
  description = "IP address for k3s controller"
  type        = string
  default     = "192.168.86.100"
}

variable "k3s_controller_cores" {
  description = "CPU cores for controller"
  type        = number
  default     = 4
}

variable "k3s_controller_memory" {
  description = "Memory in MB for controller"
  type        = number
  default     = 4096
}

variable "k3s_controller_disk_size" {
  description = "Disk size for controller"
  type        = string
  default     = "30G"
}

# k3s Worker Nodes
variable "k3s_worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "k3s_worker_vmid_start" {
  description = "Starting VMID for workers"
  type        = number
  default     = 111
}

variable "k3s_worker_hostname_prefix" {
  description = "Hostname prefix for workers"
  type        = string
  default     = "k3s-a"
}

variable "k3s_worker_ips" {
  description = "List of IP addresses for worker nodes"
  type        = list(string)
  default     = ["192.168.86.101", "192.168.86.102"]
}

variable "k3s_worker_cores" {
  description = "CPU cores for workers"
  type        = number
  default     = 4
}

variable "k3s_worker_memory" {
  description = "Memory in MB for workers"
  type        = number
  default     = 4096
}

variable "k3s_worker_disk_size" {
  description = "Disk size for workers"
  type        = string
  default     = "30G"
}

# k3s Configuration
variable "k3s_version" {
  description = "k3s version to install"
  type        = string
  default     = "v1.31.4+k3s1"
}

variable "k3s_token" {
  description = "k3s cluster token (will be auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}
