#!/usr/bin/env bash
# Check k3s cluster status

set -e

CONTROLLER_IP="${CONTROLLER_IP:-${1}}"

if [ -z "$CONTROLLER_IP" ]; then
    echo "Error: Controller IP not provided"
    echo "Usage: $0 <controller_ip>"
    echo "   or: CONTROLLER_IP=192.168.86.100 $0"
    exit 1
fi

echo "Checking k3s cluster at $CONTROLLER_IP..."
echo ""

echo "=== Node Status ==="
ssh root@$CONTROLLER_IP "kubectl get nodes -o wide"

echo ""
echo "=== System Pods ==="
ssh root@$CONTROLLER_IP "kubectl get pods -A"

echo ""
echo "=== k3s Services ==="
ssh root@$CONTROLLER_IP "systemctl status k3s --no-pager | head -20"
