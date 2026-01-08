# Manual Deployment Scripts

These scripts are **not used by Terraform** but are available for manual deployments or troubleshooting.

## Scripts

### configure-lxc.sh
Manual LXC container configuration for k3s compatibility.

**Usage:**
```bash
# On Proxmox host
./scripts/manual/configure-lxc.sh 110 k3s-c01
```

### install-k3s-controller.sh
Install k3s server on a control plane node.

**Usage:**
```bash
# On controller node
K3S_VERSION=v1.31.4+k3s1 K3S_TOKEN=your-token ./scripts/manual/install-k3s-controller.sh
```

### install-k3s-worker.sh
Install k3s agent on a worker node.

**Usage:**
```bash
# On worker node
K3S_URL=https://192.168.86.100:6443 \
K3S_TOKEN=your-token \
K3S_VERSION=v1.31.4+k3s1 \
./scripts/manual/install-k3s-worker.sh
```

### deploy-cluster.sh
Complete manual deployment without Terraform.

**Usage:**
```bash
# From local machine
source .env && ./scripts/manual/deploy-cluster.sh
```

## When to Use These

- **Manual deployments** - When you don't want to use Terraform
- **Troubleshooting** - Re-run individual installation steps
- **Testing** - Verify k3s installation process
- **Custom workflows** - Integrate into your own automation

## Terraform Users

If you're using Terraform, you **don't need these scripts**. Terraform handles everything automatically via inline provisioners in `main.tf`.
