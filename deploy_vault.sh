#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="vault"
DEFAULT_FORWARD_PORT=18200
VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"

VAULT_CHART_VERSION="0.31.0"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }
need kubectl; need helm;

echo "[Vault] Using VM IP: ${VM_IP}"
echo "[Vault] Forward port: ${DEFAULT_FORWARD_PORT}"

echo "[Vault] Create namespace..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[Vault] Add Helm repo..."
helm repo add hashicorp https://helm.releases.hashicorp.com || true
helm repo update

echo "[Vault] Install (dev mode)..."
helm upgrade --install vault hashicorp/vault \
  --namespace "${NAMESPACE}" \
  --version "$VAULT_CHART_VERSION" \
  --set "server.dev.enabled=true" \
  --wait --timeout 10m

echo "[Vault] Checking pod and service readiness..."

# Wait for Vault pod to be Ready (timeout 2 min)
timeout=120
interval=5
elapsed=0
while true; do
    pod_status=$(kubectl get pod -n "${NAMESPACE}" -l app.kubernetes.io/name=vault -o jsonpath='{.items[0].status.containerStatuses[0].ready}')
    if [[ "$pod_status" == "true" ]]; then
        echo "[Vault] Pod is ready"
        break
    fi
    if (( elapsed >= timeout )); then
        echo "[Vault] Timeout waiting for pod to be ready"
        exit 1
    fi
    sleep $interval
    (( elapsed += interval ))
done

# Check service has endpoints
if ! kubectl get endpoints -n "${NAMESPACE}" vault | grep -q "10\."; then
    echo "[Vault] Service has no endpoints yet"
    exit 1
fi

echo "[Vault] Service is available with endpoints"


echo "[Vault] Port-forward ${VM_IP}:${DEFAULT_FORWARD_PORT} -> 8200..."
pkill -f "kubectl port-forward .* ${DEFAULT_FORWARD_PORT}:8200 -n ${NAMESPACE}" || true

set +e
kubectl port-forward svc/vault -n "${NAMESPACE}" "${DEFAULT_FORWARD_PORT}:8200" --address "${VM_IP}" >/tmp/vault-portforward.log 2>&1 &
sleep 2
if ! ps -ef | grep -q "[p]ort-forward .* ${DEFAULT_FORWARD_PORT}:8200 .* ${NAMESPACE}"; then
  echo "[Vault] Binding to ${VM_IP} failed; falling back to 0.0.0.0"
  kubectl port-forward svc/vault -n "${NAMESPACE}" "${DEFAULT_FORWARD_PORT}:8200" --address 0.0.0.0 >/tmp/vault-portforward.log 2>&1 &
  sleep 2
fi
set -e

echo "========================================================"
echo " Vault (DEV) URL: http://${VM_IP}:${DEFAULT_FORWARD_PORT}"
echo " Token (dev): root"
echo " NOTE: dev mode is for labs only."
echo "========================================================"
