# Proxmox k3s Cluster with Terraform

Automated deployment of a k3s Kubernetes cluster on Proxmox using LXC containers with Terraform and Bash scripts.

## Features

- ✅ **Ubuntu 24.04 LTS** LXC containers (OCI image support)
- ✅ **1 Control Plane + 2 Worker Nodes** (configurable)
- ✅ **Terraform-managed** infrastructure as code
- ✅ **Automated k3s installation** via scripts
- ✅ **Proper LXC configuration** for k3s compatibility
- ✅ **Static IP addressing**
- ✅ **SSH key authentication**

## LXC Configuration for k3s

The LXC containers are configured with special settings required for running Kubernetes:

```bash
lxc.apparmor.profile: unconfined       # Disable AppArmor restrictions
lxc.cgroup2.devices.allow: a            # Allow all device access
lxc.cap.drop:                           # Keep all capabilities
lxc.mount.auto: proc:rw sys:rw          # Mount proc and sys as read-write
lxc.mount.entry: /dev/kmsg dev/kmsg none bind,optional,create=file  # Mount /dev/kmsg for kubelet
```

**Important**: Kernel modules must be loaded on the Proxmox host (not in containers):
- `br_netfilter` - Bridge netfilter support
- `overlay` - Overlay filesystem
- `ip_tables` - IP tables support
- `iptable_nat` - NAT support

These are automatically loaded during deployment via the main.tf configuration.

## Architecture

```
┌─────────────────────────────────────────┐
│         Proxmox Host (9.1.4+)           │
│  ┌───────────────────────────────────┐  │
│  │  k3s-c01 (Controller)             │  │
│  │  192.168.86.100                   │  │
│  │  4 cores, 4GB RAM, 30GB disk      │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  k3s-a01 (Worker)                 │  │
│  │  192.168.86.101                   │  │
│  │  4 cores, 4GB RAM, 30GB disk      │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  k3s-a02 (Worker)                 │  │
│  │  192.168.86.102                   │  │
│  │  4 cores, 4GB RAM, 30GB disk      │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

## Prerequisites

### On Your Local Machine

1. **Terraform** (>= 1.0)
```bash
# macOS
brew install terraform

# Linux
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

2. **sshpass** (for password-based SSH automation)
```bash
# macOS
brew install esolitos/ipa/sshpass

# Linux
sudo apt-get install sshpass  # Debian/Ubuntu
sudo yum install sshpass      # RHEL/CentOS
```

3. **SSH access** to Proxmox host configured

### On Proxmox Host

1. **Proxmox VE 8.0+** (tested on 9.1.4)
2. **Root password authentication** (API tokens have limitations with privileged containers)
3. **Storage pools**:
   - Storage for templates (e.g., `local`) - must support `vztmpl` content type
   - Storage for container disks (e.g., `local-lvm`, `truenas`) - must support container directories
4. **Network bridge** configured (e.g., `vmbr0`)

## Quick Start

### 1. Clone and Configure

```bash
# Clone the repository
git clone <your-repo-url>
cd proxmox_k3s_terraform

# Make scripts executable
chmod +x scripts/*.sh

# Copy and edit terraform variables
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

### 2. Update `terraform.tfvars`

```hcl
proxmox_api_url      = "https://your-proxmox-ip:8006"
proxmox_api_user     = "root@pam"  # Must use root@pam for privileged containers
proxmox_api_password = "your-password"
proxmox_node         = "proxmox"  # Your node name

# Storage configuration - separate storage for templates and containers
template_storage = "local"      # For templates (must support vztmpl)
storage_pool     = "truenas"    # For container disks (or local-lvm)

# Add your SSH public key
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E..."

# Set root password for containers
root_password = "your-secure-password"

# Network configuration
gateway    = "192.168.86.1"
nameserver = "8.8.8.8"

# Adjust IPs, hostnames, resources as needed
k3s_controller_ip = "192.168.86.30"
k3s_worker_ips = ["192.168.86.31", "192.168.86.32"]
```

### 3. Deploy with Terraform

```bash
# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy the cluster
terraform apply
```

The deployment will:
1. Download Ubuntu 24.04 LTS template
2. Create 3 LXC containers (1 controller, 2 workers)
3. Configure containers with k3s-compatible settings
4. Install k3s on all nodes
5. Join workers to the cluster

### 4. Access Your Cluster

```bash
# SSH to controller
ssh root@192.168.86.30

# Check cluster status
kubectl get nodes -o wide

# Get kubeconfig (from local machine)
ssh root@192.168.86.30 "cat /etc/rancher/k3s/k3s.yaml" > kubeconfig.yaml
# Edit kubeconfig.yaml and replace 127.0.0.1 with 192.168.86.30

# Use kubectl locally
export KUBECONFIG=./kubeconfig.yaml
kubectl get nodes
```

## Manual Deployment (Without Terraform)

If you prefer to use bash scripts without Terraform:

### 1. Create LXC Containers Manually

Create 3 Ubuntu 24.04 LXC containers via Proxmox UI or CLI with:
- 4 cores, 4GB RAM, 30GB disk
- Static IPs: 192.168.86.30, 192.168.86.31, 192.168.86.32
- Enable nesting

### 2. Configure LXC for k3s

```bash
# On Proxmox host, run for each container
./scripts/manual/configure-lxc.sh 210 k3s-c01
./scripts/manual/configure-lxc.sh 211 k3s-a01
./scripts/manual/configure-lxc.sh 212 k3s-a02

# Restart containers
pct stop 210 && pct start 210
pct stop 211 && pct start 211
pct stop 212 && pct start 212
```

### 3. Install k3s

```bash
# On controller (192.168.86.30)
ssh root@192.168.86.30
K3S_VERSION=v1.31.4+k3s1 K3S_TOKEN=$(openssl rand -hex 32) bash < scripts/manual/install-k3s-controller.sh

# Get the token
K3S_TOKEN=$(ssh root@192.168.86.30 cat /var/lib/rancher/k3s/server/node-token)

# On each worker
ssh root@192.168.86.31
K3S_URL=https://192.168.86.30:6443 K3S_TOKEN=$K3S_TOKEN bash < scripts/manual/install-k3s-worker.sh

ssh root@192.168.86.32
K3S_URL=https://192.168.86.30:6443 K3S_TOKEN=$K3S_TOKEN bash < scripts/manual/install-k3s-worker.sh
```

## LXC Configuration for k3s

These settings are critical for k3s to work in LXC containers:

```
features: nesting=1
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
lxc.mount.auto: proc:rw sys:rw
lxc.mount.entry: /dev/kmsg dev/kmsg none bind,optional,create=file
```

**Note**: Kernel modules (`br_netfilter`, `overlay`, `ip_tables`, `iptable_nat`) are automatically loaded on the Proxmox host during deployment.

## Project Structure

```
.
├── README.md
├── providers.tf              # Terraform provider configuration
├── variables.tf              # Variable definitions
├── main.tf                   # Main infrastructure code
├── outputs.tf                # Output definitions
├── terraform.tfvars.example  # Example variables file
├── .gitignore
└── scripts/
    ├── check-cluster.sh      # Check cluster health
    ├── get-kubeconfig.sh     # Retrieve kubeconfig
    ├── uninstall-k3s.sh      # Uninstall k3s
    └── manual/               # Manual deployment scripts (not used by Terraform)
        ├── README.md
        ├── configure-lxc.sh
        ├── deploy-cluster.sh
        ├── install-k3s-controller.sh
        └── install-k3s-worker.sh
```

## Useful Commands

```bash
# Terraform
terraform plan              # Preview changes
terraform apply             # Apply changes
terraform destroy           # Destroy cluster
terraform output            # Show outputs
terraform output -raw k3s_token  # Get cluster token

# Proxmox
pct list                    # List containers
pct config 210              # Show container config
pct stop 210 && pct start 210  # Restart container
pct enter 210               # Enter container console

# k3s
kubectl get nodes -o wide   # Check cluster status
kubectl get pods -A         # List all pods
kubectl describe node k3s-controller-01  # Node details

# Uninstall k3s (on nodes)
/usr/local/bin/k3s-uninstall.sh        # On controller
/usr/local/bin/k3s-agent-uninstall.sh  # On workers
```

## Customization

### Change Number of Workers

Edit `terraform.tfvars`:
```hcl
k3s_worker_count = 3  # Add more workers
```

### Change Resources

```hcl
k3s_controller_cores  = 8
k3s_controller_memory = 8192
k3s_worker_cores      = 6
k3s_worker_memory     = 6144
```

### Use Different k3s Version

```hcl
k3s_version = "v1.30.1+k3s1"
```

### Change Network

```hcl
k3s_controller_ip = "10.0.0.10"
k3s_worker_ips = ["10.0.0.11", "10.0.0.12"]  # Non-sequential IPs supported
gateway = "10.0.0.1"

# Update hostnames if needed
k3s_controller_hostname = "k3s-c01"
k3s_worker_hostnames = ["k3s-w01", "k3s-w02"]

# Update VMIDs if needed
k3s_controller_vmid = 210
k3s_worker_vmids = [211, 212]
```

## Troubleshooting

### Authentication Errors (401/403/500)
**Issue**: Terraform fails with API authentication errors.
**Solution**: Use `root@pam` with password authentication, not API tokens. Privileged containers require full root access.

```hcl
# In terraform.tfvars
proxmox_api_user     = "root@pam"
proxmox_api_password = "your-password"
```

### Storage Not Found
**Issue**: Error like `storage "local-lxc" doesn't exist`.
**Solution**: Verify storage names in Proxmox and update `terraform.tfvars`:
- `template_storage` must support `vztmpl` content (usually `local`)
- `storage_pool` must support container directories (e.g., `local-lvm`, `truenas`)

### kubelet Fails with "/dev/kmsg: no such file or directory"
**Issue**: k3s kubelet cannot start.
**Solution**: The `/dev/kmsg` device must be bind-mounted from host. This is automatically configured in `main.tf` via:
```
lxc.mount.entry: /dev/kmsg dev/kmsg none bind,optional,create=file
```
If manual setup, add this line to `/etc/pve/lxc/<vmid>.conf` and restart the container.

### Kernel Module Errors (modprobe failures)
**Issue**: Errors about `br_netfilter`, `overlay` modules.
**Solution**: Load modules on Proxmox host, not in containers:
```bash
# On Proxmox host
modprobe br_netfilter overlay ip_tables iptable_nat
echo -e "br_netfilter\noverlay\nip_tables\niptable_nat" > /etc/modules-load.d/k3s.conf
```
The deployment automatically handles this.

### Container won't start
```bash
# Check logs
pct status 210
journalctl -xe

# Verify LXC config
pct config 210
```

### k3s installation fails
```bash
# Check inside container
pct enter 210
systemctl status k3s
journalctl -u k3s -f
```

### Workers not joining
```bash
# Verify token and connectivity
ssh root@192.168.86.31
curl -k https://192.168.86.30:6443
systemctl status k3s-agent
journalctl -u k3s-agent -f
```

### Networking issues
```bash
# Check firewall on controller
iptables -L
# k3s uses ports: 6443 (API), 10250 (kubelet)
```

### SSH Connection Issues
**Issue**: Cannot SSH to containers.
**Solution**: Ensure `sshpass` is installed locally and SSH server is configured in containers. The deployment handles this automatically.

## Security Considerations

1. **Change default passwords** in `terraform.tfvars`
2. **Use SSH keys** instead of password authentication
3. **Firewall rules** - restrict access to k3s API (port 6443)
4. **Keep secrets secure** - don't commit `terraform.tfvars`
5. **Update regularly** - use recent k3s versions

## References

- [k3s Documentation](https://docs.k3s.io/)
- [Proxmox Container Documentation](https://pve.proxmox.com/wiki/Linux_Container)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Running k3s in LXC](https://gist.github.com/triangletodd/02f595cd4c0dc9aac5f7763ca2264185)

## License

MIT

## Contributing

Pull requests welcome!

