#!/usr/bin/env bash
# Install k3s on worker node

set -e

if [ -z "$K3S_URL" ] || [ -z "$K3S_TOKEN" ]; then
    echo "Error: K3S_URL and K3S_TOKEN must be set"
    echo "Usage: K3S_URL=https://192.168.86.100:6443 K3S_TOKEN=<token> $0"
    exit 1
fi

K3S_VERSION="${K3S_VERSION:-v1.31.4+k3s1}"

echo "Installing k3s ${K3S_VERSION} as agent..."
echo "Connecting to: ${K3S_URL}"

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y curl wget

# Install k3s agent
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  K3S_URL="${K3S_URL}" \
  K3S_TOKEN="${K3S_TOKEN}" \
  sh -

# Enable k3s-agent service
systemctl enable k3s-agent
systemctl start k3s-agent

echo "k3s agent installation complete!"
echo "Node should appear in cluster shortly"
