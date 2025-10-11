#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="artifactory"
DEFAULT_FORWARD_PORT=18082
VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"
SERVICE_NAME="artifactory"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }
need kubectl; need helm;

echo "[Artifactory] Using VM IP: ${VM_IP}"
echo "[Artifactory] Forward port: ${DEFAULT_FORWARD_PORT}"

echo "[Artifactory] Create namespace..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[Artifactory] Add Helm repo..."
helm repo add jfrog https://charts.jfrog.io || true
helm repo update

echo "[Artifactory] Install Artifactory via Helm..."
helm upgrade --install artifactory jfrog/artifactory-jcr \
  --namespace "${NAMESPACE}" \
  --set "artifactory.service.type=ClusterIP" \
  --wait --timeout 15m

echo "[Artifactory] Checking pod readiness..."
kubectl wait --for=condition=ready pod -l "app=artifactory" -n "${NAMESPACE}" --timeout=15m

echo "[Artifactory] Pod is ready"

echo "[Artifactory] Port-forward ${VM_IP}:${DEFAULT_FORWARD_PORT} -> 8082..."
pkill -f "kubectl port-forward .* ${DEFAULT_FORWARD_PORT}:8082 -n ${NAMESPACE}" || true

set +e
kubectl port-forward svc/${SERVICE_NAME} -n "${NAMESPACE}" "${DEFAULT_FORWARD_PORT}:8082" --address "${VM_IP}" >/tmp/artifactory-portforward.log 2>&1 &
sleep 2
if ! ps -ef | grep -q "[p]ort-forward .* ${DEFAULT_FORWARD_PORT}:8082 .* ${NAMESPACE}"; then
  echo "[Artifactory] Binding to ${VM_IP} failed; falling back to 0.0.0.0"
  kubectl port-forward svc/${SERVICE_NAME} -n "${NAMESPACE}" "${DEFAULT_FORWARD_PORT}:8082" --address 0.0.0.0 >/tmp/artifactory-portforward.log 2>&1 &
  sleep 2
fi
set -e

echo "[Artifactory] Waiting for Artifactory service to be ready to accept API calls..."
sleep 30  # give Artifactory a bit of extra time after pod is 'ready'

ART_URL="http://${VM_IP}:${DEFAULT_FORWARD_PORT}/artifactory"
DEFAULT_USER="admin"
DEFAULT_PASS="password"       # Helm chart default, unless overridden
# NEW_PASS="Jadmin123!@#"

echo "[Artifactory] Accepting EULA..."
curl -s -X POST -u "${DEFAULT_USER}:${DEFAULT_PASS}" \
  "${ART_URL}/ui/jcr/eula/accept" || true

# echo "[Artifactory] Resetting admin password..."
# curl -s -X POST -u "${DEFAULT_USER}:${DEFAULT_PASS}" \
#   -H "Content-Type: application/json" \
#   -d "{\"userName\":\"${DEFAULT_USER}\",\"oldPassword\":\"${DEFAULT_PASS}\",\"newPassword\":\"${NEW_PASS}\"}" \
#   "${ART_URL}/api/security/password" || true

echo "========================================================"
echo " Artifactory URL: ${ART_URL}/"
echo " Admin User: ${DEFAULT_USER}"
echo " Updated Admin Password: ${DEFAULT_PASS}"
echo "========================================================"
