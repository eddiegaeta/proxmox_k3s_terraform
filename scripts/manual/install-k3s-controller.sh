#!/usr/bin/env bash
# Install k3s on controller node

set -e

K3S_VERSION="${K3S_VERSION:-v1.31.4+k3s1}"
K3S_TOKEN="${K3S_TOKEN:-$(openssl rand -hex 32)}"
DISABLE_COMPONENTS="${DISABLE_COMPONENTS:-traefik}"

echo "Installing k3s ${K3S_VERSION} as controller..."
echo "K3S_TOKEN: ${K3S_TOKEN}"

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y curl wget

# Install k3s server
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  K3S_TOKEN="${K3S_TOKEN}" \
  sh -s - server \
  --disable="${DISABLE_COMPONENTS}" \
  --write-kubeconfig-mode=644 \
  --tls-san=$(hostname -I | awk '{print $1}')

# Enable k3s service
systemctl enable k3s
systemctl start k3s

# Wait for k3s to be ready
echo "Waiting for k3s to be ready..."
sleep 30

# Check status
kubectl get nodes

echo "k3s controller installation complete!"
echo "K3S_TOKEN=${K3S_TOKEN}"
echo "Save this token to join worker nodes"
