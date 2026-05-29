#!/usr/bin/env bash
# Retrieve kubeconfig from the k3s controller.
#
# Two modes:
#   (default)  Write a standalone ./kubeconfig.yaml in the current directory.
#   --merge    Merge the cluster into ~/.kube/config under a named context
#              (default: k3s-home), backing up the existing config first.
#
# Usage:
#   ./get-kubeconfig.sh <controller_ip>
#   ./get-kubeconfig.sh <controller_ip> --merge
#   ./get-kubeconfig.sh <controller_ip> --merge --context my-lab
#   CONTROLLER_IP=192.168.86.30 ./get-kubeconfig.sh --merge

set -euo pipefail

CONTROLLER_IP="${CONTROLLER_IP:-}"
MERGE=false
CONTEXT_NAME="k3s-home"
SSH_USER="root"

# Parse args: first bare (non-flag) arg is the controller IP.
while [ $# -gt 0 ]; do
  case "$1" in
    --merge)   MERGE=true; shift ;;
    --context) CONTEXT_NAME="${2:?--context requires a value}"; shift 2 ;;
    --user)    SSH_USER="${2:?--user requires a value}"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)
      echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      CONTROLLER_IP="$1"; shift ;;
  esac
done

if [ -z "$CONTROLLER_IP" ]; then
  echo "Error: Controller IP not provided" >&2
  echo "Usage: $0 <controller_ip> [--merge] [--context NAME]" >&2
  exit 1
fi

# Containers are recreated on terraform destroy/apply, so the SSH host key
# changes. Drop any stale entry so the pull doesn't fail host-key verification.
echo "Clearing any stale SSH host key for ${CONTROLLER_IP}..."
ssh-keygen -R "$CONTROLLER_IP" >/dev/null 2>&1 || true

echo "Retrieving kubeconfig from ${SSH_USER}@${CONTROLLER_IP}..."
RAW="$(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
  "${SSH_USER}@${CONTROLLER_IP}" 'cat /etc/rancher/k3s/k3s.yaml')"

if $MERGE; then
  # Rewrite the server address and rename the (k3s-default) context/cluster/user
  # so it doesn't collide with anything already in ~/.kube/config.
  REWRITTEN="$(printf '%s\n' "$RAW" | sed \
    -e "s/127.0.0.1/${CONTROLLER_IP}/g" \
    -e "s/: default/: ${CONTEXT_NAME}/g" \
    -e "s/name: default/name: ${CONTEXT_NAME}/g")"

  TMP_CFG="$(mktemp)"
  printf '%s\n' "$REWRITTEN" > "$TMP_CFG"

  mkdir -p "${HOME}/.kube"
  if [ -f "${HOME}/.kube/config" ]; then
    cp "${HOME}/.kube/config" "${HOME}/.kube/config.bak"
    echo "Backed up existing config -> ~/.kube/config.bak"
  fi

  MERGED="$(mktemp)"
  KUBECONFIG="${HOME}/.kube/config:${TMP_CFG}" kubectl config view --flatten > "$MERGED"
  mv "$MERGED" "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  rm -f "$TMP_CFG"

  kubectl config use-context "$CONTEXT_NAME"
  echo ""
  echo "Merged into ~/.kube/config as context '${CONTEXT_NAME}' (now active)."
  echo "Switch back to another cluster any time with:"
  echo "  kubectl config use-context <name>"
else
  printf '%s\n' "$RAW" | sed "s/127.0.0.1/${CONTROLLER_IP}/g" > kubeconfig.yaml
  echo "Kubeconfig saved to kubeconfig.yaml"
  echo ""
  echo "To use it:"
  echo "  export KUBECONFIG=\$(pwd)/kubeconfig.yaml"
  echo "  kubectl get nodes"
fi
