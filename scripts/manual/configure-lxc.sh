#!/usr/bin/env bash
# Manual LXC container preparation script for k3s
# Use this if you want to manually configure LXC containers instead of using Terraform

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <vmid> <container_name>"
    echo "Example: $0 110 k3s-c01"
    exit 1
fi

VMID=$1
CONTAINER_NAME=$2

echo "Configuring LXC container $VMID ($CONTAINER_NAME) for k3s..."

# Enable nesting
pct set $VMID -features nesting=1

# Make container privileged (needed for some k3s operations)
pct set $VMID --unprivileged 0

# Add custom LXC configurations to the container config file
CONFIG_FILE="/etc/pve/lxc/${VMID}.conf"

echo "Adding k3s-specific configurations to $CONFIG_FILE..."

# Check if configurations already exist
if ! grep -q "lxc.apparmor.profile" "$CONFIG_FILE"; then
    echo "lxc.apparmor.profile: unconfined" >> "$CONFIG_FILE"
fi

if ! grep -q "lxc.cgroup2.devices.allow" "$CONFIG_FILE"; then
    echo "lxc.cgroup2.devices.allow: a" >> "$CONFIG_FILE"
fi

if ! grep -q "lxc.cap.drop:" "$CONFIG_FILE"; then
    echo "lxc.cap.drop:" >> "$CONFIG_FILE"
fi

if ! grep -q "lxc.mount.auto" "$CONFIG_FILE"; then
    echo "lxc.mount.auto: proc:rw sys:rw" >> "$CONFIG_FILE"
fi

echo "Configuration complete for $CONTAINER_NAME (VMID: $VMID)"
echo "You may need to restart the container: pct stop $VMID && pct start $VMID"
