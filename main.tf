# Download Ubuntu 24.04 LTS template
resource "proxmox_virtual_environment_download_file" "ubuntu_template" {
  node_name    = var.proxmox_node
  content_type = "vztmpl"
  datastore_id = var.template_storage
  
  url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64-root.tar.xz"
  
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

# Apply additional LXC configuration directly via SSH
resource "null_resource" "configure_lxc_controller" {
  depends_on = [proxmox_virtual_environment_container.k3s_controller]
  
  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no ${var.proxmox_ssh_user}@${replace(replace(var.proxmox_api_url, "https://", ""), ":8006", "")} \
        "modprobe br_netfilter && \
         modprobe overlay && \
         modprobe ip_tables && \
         modprobe iptable_nat && \
         echo 'br_netfilter' >> /etc/modules && \
         echo 'overlay' >> /etc/modules && \
         echo 'ip_tables' >> /etc/modules && \
         echo 'iptable_nat' >> /etc/modules && \
         echo 'lxc.apparmor.profile: unconfined' >> /etc/pve/lxc/${var.k3s_controller_vmid}.conf && \
         echo 'lxc.cgroup2.devices.allow: a' >> /etc/pve/lxc/${var.k3s_controller_vmid}.conf && \
         echo 'lxc.cap.drop:' >> /etc/pve/lxc/${var.k3s_controller_vmid}.conf && \
         echo 'lxc.mount.auto: proc:rw sys:rw' >> /etc/pve/lxc/${var.k3s_controller_vmid}.conf && \
         echo 'lxc.mount.entry: /dev/kmsg dev/kmsg none bind,optional,create=file' >> /etc/pve/lxc/${var.k3s_controller_vmid}.conf && \
         pct start ${var.k3s_controller_vmid} && \
         sleep 15 && \
         pct exec ${var.k3s_controller_vmid} -- bash -c 'DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y openssh-server && sed -i \"s/#PermitRootLogin prohibit-password/PermitRootLogin yes/\" /etc/ssh/sshd_config && sed -i \"s/PasswordAuthentication no/PasswordAuthentication yes/\" /etc/ssh/sshd_config && systemctl enable ssh && systemctl restart ssh'"
    EOT
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'Controller config cleanup'"
  }
}

resource "null_resource" "configure_lxc_workers" {
  count = var.k3s_worker_count
  
  depends_on = [proxmox_virtual_environment_container.k3s_workers]
  
  provisioner "local-exec" {
    command = <<-EOT
      ssh -o StrictHostKeyChecking=no ${var.proxmox_ssh_user}@${replace(replace(var.proxmox_api_url, "https://", ""), ":8006", "")} \
        "echo 'lxc.apparmor.profile: unconfined' >> /etc/pve/lxc/${var.k3s_worker_vmid_start + count.index}.conf && \
         echo 'lxc.cgroup2.devices.allow: a' >> /etc/pve/lxc/${var.k3s_worker_vmid_start + count.index}.conf && \
         echo 'lxc.cap.drop:' >> /etc/pve/lxc/${var.k3s_worker_vmid_start + count.index}.conf && \
         echo 'lxc.mount.auto: proc:rw sys:rw' >> /etc/pve/lxc/${var.k3s_worker_vmid_start + count.index}.conf && \
         echo 'lxc.mount.entry: /dev/kmsg dev/kmsg none bind,optional,create=file' >> /etc/pve/lxc/${var.k3s_worker_vmid_start + count.index}.conf && \
         pct start ${var.k3s_worker_vmid_start + count.index} && \
         sleep 15 && \
         pct exec ${var.k3s_worker_vmid_start + count.index} -- bash -c 'DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -y openssh-server && sed -i \"s/#PermitRootLogin prohibit-password/PermitRootLogin yes/\" /etc/ssh/sshd_config && sed -i \"s/PasswordAuthentication no/PasswordAuthentication yes/\" /etc/ssh/sshd_config && systemctl enable ssh && systemctl restart ssh'"
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
    null_resource.configure_lxc_controller
  ]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for SSH to be ready..."
      sleep 45
      echo "Installing k3s on controller..."
      sshpass -p '${var.root_password}' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${var.k3s_controller_ip} bash << 'ENDSSH'
        apt-get update
        curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} K3S_TOKEN=${local.k3s_token} INSTALL_K3S_SKIP_START=true sh -s - server --disable=traefik --write-kubeconfig-mode=644
        sed -i '/ExecStartPre=.*modprobe/d' /etc/systemd/system/k3s.service
        systemctl daemon-reload
        systemctl enable k3s
        systemctl start k3s
        echo "Waiting for k3s to be ready..."
        for i in {1..60}; do
          if systemctl is-active --quiet k3s; then
            echo "k3s service is active"
            if kubectl get nodes 2>/dev/null; then
              echo "k3s is fully operational"
              break
            fi
          fi
          echo "Waiting... ($i/60)"
          sleep 5
        done
        systemctl status k3s --no-pager -l || true
        kubectl get nodes || true
ENDSSH
    EOT
  }
}

# Install k3s on workers
resource "null_resource" "install_k3s_workers" {
  count = var.k3s_worker_count
  
  depends_on = [
    null_resource.configure_lxc_workers,
    null_resource.install_k3s_controller
  ]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for SSH to be ready..."
      sleep 45
      echo "Installing k3s on worker ${count.index + 1}..."
      sshpass -p '${var.root_password}' ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR root@${var.k3s_worker_ips[count.index]} bash << 'ENDSSH'
        apt-get update
        curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${var.k3s_version} K3S_URL=https://${var.k3s_controller_ip}:6443 K3S_TOKEN=${local.k3s_token} INSTALL_K3S_SKIP_START=true sh -
        sed -i '/ExecStartPre=.*modprobe/d' /etc/systemd/system/k3s-agent.service
        systemctl daemon-reload
        systemctl enable k3s-agent
        systemctl start k3s-agent
        echo "Worker ${count.index + 1} k3s-agent started"
        sleep 20
ENDSSH
    EOT
  }
}
