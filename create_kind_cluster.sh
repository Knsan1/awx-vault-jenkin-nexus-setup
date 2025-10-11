#!/bin/bash
set -euo pipefail

# INOTIFY FIX
sudo sysctl fs.inotify.max_user_watches=524288
sudo sysctl fs.inotify.max_user_instances=512

VM_IP=$(./detect_vm_ip.sh)
K8S_VERSION="${K8S_VERSION:-v1.33.1}"

cat <<EOF | kind create cluster --name kind --image kindest/node:$K8S_VERSION --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5000"]
    endpoint = ["http://registry:5000"]
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF

# Connect kind nodes to shared network so they can reach registry and Jenkins
for node in $(docker ps --filter "name=kind" --format '{{.Names}}'); do
    docker network connect kindnet "$node" || true
done
