#!/usr/bin/env bash
# Deploy k3s cluster manually without Terraform

set -e

# Configuration
CONTROLLER_IP="${CONTROLLER_IP}"
WORKER_IPS="${WORKER_IPS}"
K3S_VERSION="${K3S_VERSION:-v1.31.4+k3s1}"
K3S_TOKEN="${K3S_TOKEN:-$(openssl rand -hex 32)}"
ROOT_PASSWORD="${ROOT_PASSWORD}"

if [ -z "$CONTROLLER_IP" ] || [ -z "$WORKER_IPS" ] || [ -z "$ROOT_PASSWORD" ]; then
    echo "Error: CONTROLLER_IP, WORKER_IPS, and ROOT_PASSWORD must be set"
    echo "Usage: CONTROLLER_IP=192.168.86.100 WORKER_IPS='192.168.86.101 192.168.86.102' ROOT_PASSWORD='pass' $0"
    echo "Or source a .env file: source .env && $0"
    exit 1
fi

echo "Deploying k3s cluster..."
echo "Controller: $CONTROLLER_IP"
echo "Workers: $WORKER_IPS"
echo "Version: $K3S_VERSION"
echo "Token: $K3S_TOKEN"
echo ""

# Install k3s on controller
echo "=== Installing k3s on controller ==="
sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$CONTROLLER_IP \
  "K3S_VERSION=$K3S_VERSION K3S_TOKEN=$K3S_TOKEN bash -s" < scripts/install-k3s-controller.sh

echo ""
echo "Waiting for controller to be ready..."
sleep 30

# Install k3s on workers
for WORKER_IP in $WORKER_IPS; do
    echo "=== Installing k3s on worker $WORKER_IP ==="
    sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$WORKER_IP \
      "K3S_VERSION=$K3S_VERSION K3S_URL=https://$CONTROLLER_IP:6443 K3S_TOKEN=$K3S_TOKEN bash -s" < scripts/install-k3s-worker.sh
    echo ""
    sleep 10
done

echo "=== Cluster Status ==="
sshpass -p "$ROOT_PASSWORD" ssh -o StrictHostKeyChecking=no root@$CONTROLLER_IP "kubectl get nodes -o wide"

echo ""
echo "Deployment complete!"
echo "Access your cluster: ssh root@$CONTROLLER_IP"
echo "K3S_TOKEN: $K3S_TOKEN"
