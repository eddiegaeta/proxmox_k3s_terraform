# Proxmox k3s Cluster with Terraform

Automated deployment of a k3s Kubernetes cluster on Proxmox using LXC containers with Terraform and Bash scripts.

## Features

- ✅ **Ubuntu 24.04 LTS** LXC containers (OCI image support)
- ✅ **1 Control Plane + 2 Worker Nodes** (configurable)
- ✅ **Terraform-managed** infrastructure as code
- ✅ **Automated k3s installation** via scripts
- ✅ **Fail-fast install** — install steps run with `set -eo pipefail` and verify the `k3s` binary + service before reporting success, so a failed install fails the `apply` instead of silently passing
- ✅ **No false drift** — containers use `lifecycle { ignore_changes = [started] }` so re-running `apply` never tries to stop a healthy node
- ✅ **One-command kubeconfig** — `scripts/get-kubeconfig.sh --merge` pulls and merges the cluster into `~/.kube/config`
- ✅ **Proper LXC configuration** for k3s compatibility
- ✅ **Static IP addressing**
- ✅ **SSH key authentication**

## LXC Configuration for k3s

The LXC containers run privileged with `features: nesting=1`, plus these settings (applied to `/etc/pve/lxc/<vmid>.conf` on the host) required for running Kubernetes:

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
│         Proxmox Host (9.1.4+)            │
│  ┌───────────────────────────────────┐   │
│  │  k3s-controller-01  (CT 210)      │   │
│  │  192.168.86.30                    │   │
│  │  4 cores, 4GB RAM, 30GB disk      │   │
│  └───────────────────────────────────┘   │
│  ┌───────────────────────────────────┐   │
│  │  k3s-worker-01  (CT 211)          │   │
│  │  192.168.86.31                    │   │
│  │  4 cores, 4GB RAM, 30GB disk      │   │
│  └───────────────────────────────────┘   │
│  ┌───────────────────────────────────┐   │
│  │  k3s-worker-02  (CT 212)          │   │
│  │  192.168.86.32                    │   │
│  │  4 cores, 4GB RAM, 30GB disk      │   │
│  └───────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

> Default IPs/VMIDs shown above; all are configurable in `terraform.tfvars`. Workers are created from a `k3s_worker_count` + `k3s_worker_vmid_start` base, and the controller is started **stopped** then brought up by the LXC-config provisioner (see "How deployment works" below).

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
2. Create 3 LXC containers (1 controller, 2 workers) — created **stopped**
3. Configure containers with k3s-compatible settings, then start them
4. Install k3s on the controller (verifying the binary + service before continuing)
5. Install k3s-agent on each worker and join them to the cluster (also verified)

### 4. Access Your Cluster

The easiest way to get a working local `kubectl` is the helper script. It pulls the
kubeconfig from the controller, rewrites the server address from `127.0.0.1` to the
controller IP, and (with `--merge`) merges it into `~/.kube/config` under a named context.

```bash
# Merge into ~/.kube/config as context "k3s-home" and switch to it
./scripts/get-kubeconfig.sh 192.168.86.30 --merge

kubectl get nodes -o wide
```

Other modes:

```bash
# Standalone file instead of merging (writes ./kubeconfig.yaml)
./scripts/get-kubeconfig.sh 192.168.86.30
export KUBECONFIG=$(pwd)/kubeconfig.yaml

# Custom context name when merging
./scripts/get-kubeconfig.sh 192.168.86.30 --merge --context homelab
```

> ⚠️ `kubeconfig.yaml` contains your cluster's **admin credentials** and is git-ignored.
> Don't commit it. The `--merge` flow backs up your existing `~/.kube/config` to
> `~/.kube/config.bak` and chmods the result to `600`.

You can also just SSH in directly:

```bash
ssh root@192.168.86.30
kubectl get nodes -o wide
```

### How deployment works (and why)

A few non-obvious design points worth knowing before you re-run things:

- **Containers are created `started = false`.** The k3s-specific LXC settings
  (`apparmor`, `cgroup2.devices`, `/dev/kmsg` mount) are written to the container's
  `.conf` on the Proxmox host, then the container is started via `pct start`. Starting
  it *after* the config is what makes k3s work.
- **`lifecycle { ignore_changes = [started] }`** is set on both container resources.
  Once the provisioners start a container, its real state is `started = true`, which
  would otherwise conflict with the `started = false` in config and make every later
  `apply` try to stop the node (the bpg provider errors with `no options specified`).
  Ignoring that field keeps applies idempotent.
- **Install steps fail loudly.** The controller/worker install provisioners run with
  `set -eo pipefail` and explicitly check `command -v k3s` and `systemctl is-active`
  before exiting 0. If an install half-fails, the `apply` fails — you won't get a
  "successful" run with a node missing the `k3s` binary.

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
./scripts/manual/configure-lxc.sh 210 k3s-controller-01
./scripts/manual/configure-lxc.sh 211 k3s-worker-01
./scripts/manual/configure-lxc.sh 212 k3s-worker-02

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
    ├── get-kubeconfig.sh     # Retrieve kubeconfig (supports --merge into ~/.kube/config)
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

# Kubeconfig (local)
./scripts/get-kubeconfig.sh 192.168.86.30 --merge   # merge into ~/.kube/config (context k3s-home)
./scripts/get-kubeconfig.sh 192.168.86.30           # write standalone ./kubeconfig.yaml
./scripts/get-kubeconfig.sh --help                  # all options

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

# Update hostnames if needed (workers are <prefix>NN, e.g. k3s-worker-01)
k3s_controller_hostname    = "k3s-controller-01"
k3s_worker_hostname_prefix = "k3s-worker-"

# Update VMIDs if needed (workers are assigned start, start+1, ...)
k3s_controller_vmid   = 210
k3s_worker_vmid_start = 211
```

## Rebuilding the Cluster (destroy + apply)

Tearing the cluster down and standing it back up is common in a homelab. A clean cycle is:

```bash
terraform destroy
terraform apply
./scripts/get-kubeconfig.sh 192.168.86.30 --merge   # refresh local kubeconfig
```

**Callouts for rebuilds** — these bit us and are easy to hit again:

- **SSH host keys change.** New containers get new host keys, so `ssh`/`kubectl`-over-SSH
  will fail with `REMOTE HOST IDENTIFICATION HAS CHANGED`. Clear the old key per node:
  ```bash
  ssh-keygen -R 192.168.86.30   # repeat for .31, .32
  ```
  `get-kubeconfig.sh` does this automatically for the controller.
- **The k3s token regenerates if it's not pinned.** When `k3s_token` is empty, Terraform
  generates a random one and stores it **only in state**. If state is lost/reset, a new
  token is generated and any pre-existing workers can no longer join. To avoid this, pin a
  fixed token in `terraform.tfvars`:
  ```hcl
  k3s_token = "your-long-fixed-shared-secret"
  ```
- **Always `destroy` before deleting containers by hand.** If you delete containers in the
  Proxmox UI without updating state (or a partial apply leaves them out of state), the next
  `apply` fails with `CT <id> already exists` (see Troubleshooting). Prefer `terraform destroy`.

## Troubleshooting

### `CT <id> already exists on node`
**Issue**: `apply` fails to create a container whose VMID already exists on Proxmox —
typically an orphan left by a partial apply or a manual deletion that didn't update state.
**Solution**: Remove the orphaned container on the Proxmox host, then re-apply:
```bash
# On the Proxmox host
pct stop <id>  && pct destroy <id>
```
If the container *should* be managed but isn't in state, you can instead
`terraform import` it — but for worker nodes a destroy/recreate is usually cleaner because
a fresh node picks up the current k3s token automatically.

### `error updating container: ... no options specified` (started drift)
**Issue**: `apply` errors trying to modify the controller, showing `started = true -> false`.
**Cause**: The container is running (started by the provisioner) but config says
`started = false`, so Terraform tries a `started`-only update, which the bpg provider rejects.
**Solution**: Already handled — both container resources set
`lifecycle { ignore_changes = [started] }`. If you removed that block, add it back.

### `REMOTE HOST IDENTIFICATION HAS CHANGED` after a rebuild
**Issue**: SSH refuses to connect to a recreated node.
**Solution**: The host key changed with the new container. Clear the stale entry:
```bash
ssh-keygen -R 192.168.86.30   # repeat per node IP
```

### Install reported success but a node has no `k3s` binary
This should no longer happen — install steps now `set -eo pipefail` and verify
`command -v k3s` + the service before exiting 0, so a failed install fails the `apply`.
If you see it on an older state, re-run the install for that node:
```bash
terraform taint null_resource.install_k3s_controller   # or install_k3s_workers[N]
terraform apply
```

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
4. **Keep secrets secure** - `terraform.tfvars`, `terraform.tfstate` (contains the k3s token), and `kubeconfig.yaml` (cluster admin creds) are all git-ignored. Don't commit them.
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

