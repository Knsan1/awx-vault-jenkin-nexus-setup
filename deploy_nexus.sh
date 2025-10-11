#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="nexus"
DEFAULT_FORWARD_PORT=18081
VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"
SERVICE_NAME="nexus"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }
need kubectl; need helm;

echo "[Nexus] Using VM IP: ${VM_IP}"
echo "[Nexus] Forward port: ${DEFAULT_FORWARD_PORT}"

echo "[Nexus] Create namespace..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[Nexus] Add Helm repo..."
helm repo add sonatype https://sonatype.github.io/helm3-charts/ || true
helm repo update

echo "[Nexus] Install Nexus via Helm..."
helm upgrade --install "${SERVICE_NAME}" sonatype/nexus-repository-manager \
  --namespace "${NAMESPACE}" \
  --set "nexus.livenessProbe.failureThreshold=10" \
  --set "nexus.readinessProbe.failureThreshold=10" \
  --set "persistence.enabled=false" \
  --wait --timeout 15m

echo "[Nexus] Checking pod readiness..."
kubectl rollout status deployment/${SERVICE_NAME}-nexus-repository-manager -n "${NAMESPACE}" --timeout=15m

echo "[Nexus] Pod is ready"

echo "[Nexus] Port-forward ${VM_IP}:${DEFAULT_FORWARD_PORT} -> 8081..."
pkill -f "kubectl port-forward .* ${DEFAULT_FORWARD_PORT}:8081 -n ${NAMESPACE}" || true

set +e
kubectl port-forward svc/${SERVICE_NAME}-nexus-repository-manager -n "${NAMESPACE}" "${DEFAULT_FORWARD_PORT}:8081" --address "${VM_IP}" >/tmp/nexus-portforward.log 2>&1 &
sleep 2
if ! ps -ef | grep -q "[p]ort-forward .* ${DEFAULT_FORWARD_PORT}:8081 .* ${NAMESPACE}"; then
  echo "[Nexus] Binding to ${VM_IP} failed; falling back to 0.0.0.0"
  kubectl port-forward svc/${SERVICE_NAME} -n "${NAMESPACE}" "${DEFAULT_FORWARD_PORT}:8081" --address 0.0.0.0 >/tmp/nexus-portforward.log 2>&1 &
  sleep 2
fi
set -e

echo "[Nexus] Waiting for Nexus service to be ready to accept API calls..."
sleep 30  # give Nexus extra time after pod is 'ready'

NEXUS_URL="http://${VM_IP}:${DEFAULT_FORWARD_PORT}"
DEFAULT_USER="admin"
# Default password is stored in the pod at /nexus-data/admin.password

echo "[Nexus] Retrieve initial admin password..."
ADMIN_PASS=$(kubectl exec -it deploy/${SERVICE_NAME}-nexus-repository-manager -n "${NAMESPACE}" -- cat /nexus-data/admin.password 2>/dev/null | tr -d '\r')

echo "========================================================"
echo " Nexus URL: ${NEXUS_URL}"
echo " Admin User: ${DEFAULT_USER}"
echo " Initial Admin Password: ${ADMIN_PASS}"
echo "========================================================"
