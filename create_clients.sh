#!/usr/bin/env bash
set -euo pipefail

# Parse arguments: -n num_clients, -p starting_port
NUM="${1:-}"
while getopts "n:p:" opt; do
  case $opt in
    n) NUM="$OPTARG";;
    p) START_PORT="$OPTARG";;
  esac
done
shift $((OPTIND-1))
NUM="${NUM:-2}"
START_PORT="${START_PORT:-2222}"

VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"
KEY_BASE="./awx_client_key"
AUTH_DIR="./authorized_keys"
IMAGE_NAME="awx-ssh-client"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }
need docker

mkdir -p "${AUTH_DIR}"

# Generate SSH key if not present
if [ ! -f "${KEY_BASE}" ]; then
  echo "[Clients] Generating SSH keypair ${KEY_BASE}{,.pub}"
  ssh-keygen -t ed25519 -N "" -f "${KEY_BASE}" >/dev/null
fi
PUBKEY="$(cat "${KEY_BASE}.pub")"

# Write pubkey into ansible's authorized_keys
echo "${PUBKEY}" > "${AUTH_DIR}/authorized_keys"
chmod 600 "${AUTH_DIR}/authorized_keys"

##Create nfs_share Point
mkdir -p nfs_share
chmod 777 nfs_share
echo "This is the nfs share file" > nfs_share/share_file.txt
# # Build the custom Docker image
# echo "[Clients] Building Docker image: ${IMAGE_NAME}"
# docker build -t "${IMAGE_NAME}" ./docker_image

# Create containers
for i in $(seq 1 "${NUM}"); do
  name="awx-client-${i}"
  port=$((START_PORT + i - 1))

  echo "[Clients] Creating ${name} on ${VM_IP}:${port}"
  docker rm -f "${name}" >/dev/null 2>&1 || true

  docker run -d --name "${name}" \
    -p "${port}:22" \
    --network kindnet \
    --privileged \
    -v $(pwd)/nfs_share:/share \
    --restart unless-stopped \
    "${IMAGE_NAME}"

  docker cp ./authorized_keys/authorized_keys "${name}":/home/ansible/.ssh/authorized_keys
  docker exec "${name}" chown ansible:ansible /home/ansible/.ssh/authorized_keys
  docker exec "${name}" chmod 600 /home/ansible/.ssh/authorized_keys

  echo "  -> ssh ansible@${VM_IP} -p ${port}"
done

echo "========================================================"
echo " Created ${NUM} SSH clients. AWX can reach them at:"
for i in $(seq 1 "${NUM}"); do
  port=$((START_PORT + i - 1))
  echo "   client-${i}: ansible_host=${VM_IP} ansible_port=${port} ansible_user=ansible"
done
echo " Private key for AWX credential: $(realpath "${KEY_BASE}")"
echo "========================================================"

# Verify container status
docker ps --filter "name=awx-client-"
