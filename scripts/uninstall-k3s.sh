#!/usr/bin/env bash
# Uninstall k3s from nodes

set -e

NODE_TYPE="${1:-agent}"

if [ "$NODE_TYPE" = "server" ] || [ "$NODE_TYPE" = "controller" ]; then
    echo "Uninstalling k3s server..."
    if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
        /usr/local/bin/k3s-uninstall.sh
    else
        echo "k3s-uninstall.sh not found"
    fi
else
    echo "Uninstalling k3s agent..."
    if [ -f /usr/local/bin/k3s-agent-uninstall.sh ]; then
        /usr/local/bin/k3s-agent-uninstall.sh
    else
        echo "k3s-agent-uninstall.sh not found"
    fi
fi

echo "k3s uninstalled"
