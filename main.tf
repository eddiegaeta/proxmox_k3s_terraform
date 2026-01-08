# Download Ubuntu 24.04 LTS template
resource "proxmox_virtual_environment_download_file" "ubuntu_template" {
  node_name    = var.proxmox_node
  content_type = "vztmpl"
  datastore_id = var.storage_pool
  
  url = "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64-lxc.tar.xz"
  
  overwrite          = false
  overwrite_unmanaged = false
}

# Generate random token if not provided
resource "random_password" "k3s_token" {
  count   = var.k3s_token == "" ? 1 : 0
  length  = 64
  special = false
}

locals {
  k3s_token = var.k3s_token != "" ? var.k3s_token : random_password.k3s_token[0].result
}

# k3s Control Plane Node
resource "proxmox_virtual_environment_container" "k3s_controller" {
  description = "k3s Control Plane Node"
  node_name   = var.proxmox_node
  vm_id       = var.k3s_controller_vmid
  
  initialization {
    hostname = var.k3s_controller_hostname
    
    ip_config {
      ipv4 {
        address = "${var.k3s_controller_ip}/24"
        gateway = var.gateway
      }
    }
    
    dns {
      servers = [var.nameserver]
    }
    
    user_account {
      keys     = [var.ssh_public_key]
      password = var.root_password
    }
  }
  
  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }
  
  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_template.id
    type            = "ubuntu"
  }
  
  cpu {
    cores = var.k3s_controller_cores
  }
  
  memory {
    dedicated = var.k3s_controller_memory
    swap      = 0
  }
  
  disk {
    datastore_id = var.storage_pool
    size         = parseint(regex("^([0-9]+)", var.k3s_controller_disk_size)[0], 10)
  }
  
  features {
    nesting = true
  }
  
  console {
    enabled   = true
    type      = "console"
    tty_count = 2
  }
  
  # Run as privileged container for k3s
  unprivileged = false
  
  unprivileged = false
  
  startup {
    order      = 1
    up_delay   = 30
    down_delay = 30
  }
  
  tags = ["k3s", "controller"]
  
  started = false  # Start after configuration
}

# k3s Worker Nodes
resource "proxmox_virtual_environment_container" "k3s_workers" {
  count = var.k3s_worker_count
  
  description = "k3s Worker Node ${count.index + 1}"
  node_name   = var.proxmox_node
  vm_id       = var.k3s_worker_vmid_start + count.index
  
  initialization {
    hostname = format("%s%02d", var.k3s_worker_hostname_prefix, count.index + 1)
    
    ip_config {
      ipv4 {
        address = "${var.k3s_worker_ips[count.index]}/24"
        gateway = var.gateway
      }
    }
    
    dns {
      servers = [var.nameserver]
    }
    
    user_account {
      keys     = [var.ssh_public_key]
      password = var.root_password
    }
  }
  
  network_interface {
    name   = "eth0"
    bridge = var.network_bridge
  }
  
  operating_system {
    template_file_id = proxmox_virtual_environment_download_file.ubuntu_template.id
    type            = "ubuntu"
  }
  
  cpu {
    cores = var.k3s_worker_cores
  }
  
  memory {
    dedicated = var.k3s_worker_memory
    swap      = 0
  }
  
  disk {
    datastore_id = var.storage_pool
    size         = parseint(regex("^([0-9]+)", var.k3s_worker_disk_size)[0], 10)
  }
  
  features {
    nesting = true
  }
  
  console {
    enabled   = true
    type      = "console"
    tty_count = 2
  }
  
  # Run as privileged container for k3s
  unprivileged = false
  
  startup {
    order      = 2
    up_delay   = 30
    down_delay = 30
  }
  
  tags = ["k3s", "worker"]
  
  started = false  # Start after configuration
  
  depends_on = [proxmox_virtual_environment_container.k3s_controller]
}

# Apply additional LXC configuration via Proxmox API file manipulation
resource "proxmox_virtual_environment_file" "lxc_controller_config" {
  depends_on = [proxmox_virtual_environment_container.k3s_controller]
  
  node_name    = var.proxmox_node
  datastore_id = "local"
  
  content_type = "snippets"
  
  source_raw {
    data = <<-EOT
      lxc.apparmor.profile: unconfined
      lxc.cgroup2.devices.allow: a
      lxc.cap.drop:
      lxc.mount.auto: proc:rw sys:rw
    EOT
    
    file_name = "k3s-controller-${var.k3s_controller_vmid}.conf"
  }
}

# Apply config via provisioner (still needed for appending to LXC config)
resource "null_resource" "configure_lxc_controller" {
  depends_on = [
    proxmox_virtual_environment_container.k3s_controller,
    proxmox_virtual_environment_file.lxc_controller_config
  ]
  
  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no ${var.proxmox_ssh_user}@${replace(var.proxmox_api_url, "https://", "")} \
        "cat /var/lib/vz/snippets/k3s-controller-${var.k3s_controller_vmid}.conf >> /etc/pve/lxc/${var.k3s_controller_vmid}.conf && \
         pct start ${var.k3s_controller_vmid}"
    EOT
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Controller config cleanup'"
  }
}

resource "proxmox_virtual_environment_file" "lxc_worker_config" {
  count = var.k3s_worker_count
  
  depends_on = [proxmox_virtual_environment_container.k3s_workers]
  
  node_name    = var.proxmox_node
  datastore_id = "local"
  
  content_type = "snippets"
  
  source_raw {
    data = <<-EOT
      lxc.apparmor.profile: unconfined
      lxc.cgroup2.devices.allow: a
      lxc.cap.drop:
      lxc.mount.auto: proc:rw sys:rw
    EOT
    
    file_name = "k3s-worker-${var.k3s_worker_vmid_start + count.index}.conf"
  }
}

resource "null_resource" "configure_lxc_workers" {
  count = var.k3s_worker_count
  
  depends_on = [
    proxmox_virtual_environment_container.k3s_workers,
    proxmox_virtual_environment_file.lxc_worker_config
  ]
  
  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no ${var.proxmox_ssh_user}@${replace(var.proxmox_api_url, "https://", "")} \
        "cat /var/lib/vz/snippets/k3s-worker-${var.k3s_worker_vmid_start + count.index}.conf >> /etc/pve/lxc/${var.k3s_worker_vmid_start + count.index}.conf && \
         pct start ${var.k3s_worker_vmid_start + count.index}"
    EOT
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Worker config cleanup'"
  }
}

# Install k3s on controller
resource "null_resource" "install_k3s_controller" {
  depends_on = [
    null_resource.configure_lxc_controller,
    proxmox_virtual_environment_container.k3s_controller
  ]
  
  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} K3S_TOKEN=${local.k3s_token} sh -s - server --disable=traefik --write-kubeconfig-mode=644",
      "systemctl enable k3s",
      "sleep 30"
    ]
    
    connection {
      type     = "ssh"
      user     = "root"
      host     = var.k3s_controller_ip
      password = var.root_password
    }
  }
}

# Install k3s on workers
resource "null_resource" "install_k3s_workers" {
  count = var.k3s_worker_count
  
  depends_on = [
    null_resource.configure_lxc_workers,
    null_resource.install_k3s_controller,
    proxmox_virtual_environment_container.k3s_workers
  ]
  
  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} K3S_URL=https://${var.k3s_controller_ip}:6443 K3S_TOKEN=${local.k3s_token} sh -",
      "systemctl enable k3s-agent"
    ]
    
    connection {
      type     = "ssh"
      user     = "root"
      host     = var.k3s_worker_ips[count.index]
      password = var.root_password
    }
  }
}
