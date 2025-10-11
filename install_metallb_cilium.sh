#!/bin/bash
set -euo pipefail

metallb_version="v0.14.5"
cilium_version="1.17.4"

ctx="kind-kind"

echo "[*] Installing Cilium"
cilium install --context "$ctx" --version "$cilium_version" --wait

echo "[*] Installing MetalLB"
kubectl --context "$ctx" apply -f \
  "https://raw.githubusercontent.com/metallb/metallb/${metallb_version}/config/manifests/metallb-native.yaml"

kubectl --context "$ctx" -n metallb-system wait --for=condition=Available deployment/controller --timeout=300s

# Example IP pool range — must match your docker network range
start_ip="172.18.200.200"
end_ip="172.18.200.250"

cat <<EOF | kubectl --context "$ctx" apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: pool-1
  namespace: metallb-system
spec:
  addresses:
  - ${start_ip}-${end_ip}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: adv-1
  namespace: metallb-system
EOF
