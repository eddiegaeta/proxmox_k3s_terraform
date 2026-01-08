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

## Architecture

```
┌─────────────────────────────────────────┐
│         Proxmox Host (9.1.4+)           │
│  ┌───────────────────────────────────┐  │
│  │  k3s-c01 (Controller)             │  │
│  │  192.168.86.100                   │  │
│  │  4 cores, 4GB RAM, 38GB disk      │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  k3s-a01 (Worker)                 │  │
│  │  192.168.86.101                   │  │
│  │  4 cores, 4GB RAM, 38GB disk      │  │
│  └───────────────────────────────────┘  │
│  ┌───────────────────────────────────┐  │
│  │  k3s-a02 (Worker)                 │  │
│  │  192.168.86.102                   │  │
│  │  4 cores, 4GB RAM, 38GB disk      │  │
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

2. **SSH access** to Proxmox host configured

### On Proxmox Host

1. **Proxmox VE 9.1.4+** (for OCI image support)
2. **API user with appropriate permissions**
3. **Storage pool** for LXC containers (e.g., `local-lxc`, `truenas`)
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
proxmox_api_password = "your-password"
proxmox_node         = "proxmox"  # Your node name
storage_pool         = "local-lxc"  # Your storage

# Add your SSH public key
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E..."

# Set root password for containers
root_password = "your-secure-password"

# Network configuration
gateway    = "192.168.86.1"
nameserver = "8.8.8.8"

# Adjust IPs, hostnames, resources as needed
k3s_controller_ip = "192.168.86.100"
k3s_worker_ips = ["192.168.86.101", "192.168.86.102"]  # Specify each worker IP
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
ssh root@192.168.86.100

# Check cluster status
kubectl get nodes -o wide

# Get kubeconfig (from local machine)
ssh root@192.168.86.100 "cat /etc/rancher/k3s/k3s.yaml" > kubeconfig.yaml
# Edit kubeconfig.yaml and replace 127.0.0.1 with 192.168.86.100

# Use kubectl locally
export KUBECONFIG=./kubeconfig.yaml
kubectl get nodes
```

## Manual Deployment (Without Terraform)

If you prefer to use bash scripts without Terraform:

### 1. Create LXC Containers Manually

Create 3 Ubuntu 24.04 LXC containers via Proxmox UI or CLI with:
- 4 cores, 4GB RAM, 38GB disk
- Static IPs: 192.168.86.100, 192.168.86.101, 192.168.86.102
- Enable nesting

### 2. Configure LXC for k3s

```bash
# On Proxmox host, run for each container
./scripts/configure-lxc.sh 110 k3s-c01
./scripts/configure-lxc.sh 111 k3s-a01
./scripts/configure-lxc.sh 112 k3s-a02

# Restart containers
pct stop 110 && pct start 110
pct stop 111 && pct start 111
pct stop 112 && pct start 112
```

### 3. Install k3s

```bash
# On controller (192.168.86.100)
ssh root@192.168.86.100
curl -sfL https://raw.githubusercontent.com/your-repo/main/scripts/install-k3s-controller.sh | bash

# Get the token
K3S_TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)

# On each worker
ssh root@192.168.86.101
K3S_URL=https://192.168.86.100:6443 K3S_TOKEN=$K3S_TOKEN bash < install-k3s-worker.sh

ssh root@192.168.86.102
K3S_URL=https://192.168.86.100:6443 K3S_TOKEN=$K3S_TOKEN bash < install-k3s-worker.sh
```

## LXC Configuration for k3s

These settings are critical for k3s to work in LXC containers:

```
features: nesting=1
lxc.apparmor.profile: unconfined
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
lxc.mount.auto: proc:rw sys:rw
```

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
    ├── configure-lxc.sh          # Configure LXC for k3s
    ├── install-k3s-controller.sh # Install k3s server
    ├── install-k3s-worker.sh     # Install k3s agent
    ├── uninstall-k3s.sh          # Uninstall k3s
    └── deploy-cluster.sh         # Manual deployment script
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
pct config 110              # Show container config
pct stop 110 && pct start 110  # Restart container
pct enter 110               # Enter container console

# k3s
kubectl get nodes -o wide   # Check cluster status
kubectl get pods -A         # List all pods
kubectl describe node k3s-c01  # Node details

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
```

## Troubleshooting

### Container won't start
```bash
# Check logs
pct status 110
journalctl -xe

# Verify LXC config
pct config 110
```

### k3s installation fails
```bash
# Check inside container
pct enter 110
systemctl status k3s
journalctl -u k3s -f
```

### Workers not joining
```bash
# Verify token and connectivity
ssh root@192.168.86.101
curl -k https://192.168.86.100:6443
systemctl status k3s-agent
journalctl -u k3s-agent -f
```

### Networking issues
```bash
# Check firewall on controller
iptables -L
# k3s uses ports: 6443 (API), 10250 (kubelet)
```

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

