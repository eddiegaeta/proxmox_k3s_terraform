#!/usr/bin/env bash
# Retrieve kubeconfig from k3s controller

set -e

CONTROLLER_IP="${CONTROLLER_IP:-${1}}"

if [ -z "$CONTROLLER_IP" ]; then
    echo "Error: Controller IP not provided"
    echo "Usage: $0 <controller_ip>"
    echo "   or: CONTROLLER_IP=192.168.86.100 $0"
    exit 1
fi

echo "Retrieving kubeconfig from $CONTROLLER_IP..."

# Get kubeconfig and replace localhost with actual IP
ssh root@$CONTROLLER_IP "cat /etc/rancher/k3s/k3s.yaml" | \
  sed "s/127.0.0.1/$CONTROLLER_IP/g" > kubeconfig.yaml

echo "Kubeconfig saved to kubeconfig.yaml"
echo ""
echo "To use it:"
echo "  export KUBECONFIG=\$(pwd)/kubeconfig.yaml"
echo "  kubectl get nodes"
