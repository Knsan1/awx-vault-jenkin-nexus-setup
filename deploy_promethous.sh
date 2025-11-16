#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="monitoring"
CHART_VERSION="79.0.0"
VALUES_FILE="prometheus-values.yml"

DEFAULT_GRAFANA_PORT=19080
DEFAULT_PROM_PORT=19090

# Detect VM IP
VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }

need kubectl
need helm

echo "[Prometheus] Using VM IP: ${VM_IP}"
echo "[Prometheus] Grafana port: ${DEFAULT_GRAFANA_PORT}"
echo "[Prometheus] Prometheus port: ${DEFAULT_PROM_PORT}"

echo "[Prometheus] Creating namespace..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[Prometheus] Adding Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

echo "[Prometheus] Installing kube-prometheus-stack..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace "${NAMESPACE}" \
  --version "$CHART_VERSION" \
  -f "$VALUES_FILE" \
  --wait --timeout 10m

echo "[Prometheus] Waiting for Grafana pod to be Ready..."

# Wait for Grafana pod readiness (timeout 2min)
timeout=120
interval=5
elapsed=0
while true; do
    pod_status=$(kubectl get pod -n "${NAMESPACE}" -l "app.kubernetes.io/name=grafana" \
                 -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "")
    if [[ "$pod_status" == "true" ]]; then
        echo "[Prometheus] Grafana pod is ready"
        break
    fi

    if (( elapsed >= timeout )); then
        echo "[Prometheus] Timeout waiting for Grafana pod to be ready"
        exit 1
    fi

    sleep $interval
    (( elapsed += interval ))
done

echo "[Prometheus] Checking Grafana service endpoints..."
if ! kubectl get endpoints -n "${NAMESPACE}" prometheus-grafana | grep -q "10\."; then
    echo "[Prometheus] Grafana service has no endpoints yet"
    exit 1
fi

echo "[Prometheus] Grafana service is available."

echo "[Prometheus] Starting port-forward for Grafana..."
pkill -f "kubectl port-forward .* ${DEFAULT_GRAFANA_PORT}:80 -n ${NAMESPACE}" || true

set +e
kubectl port-forward svc/prometheus-grafana -n "${NAMESPACE}" \
    "${DEFAULT_GRAFANA_PORT}:80" --address "${VM_IP}" >/tmp/grafana-portforward.log 2>&1 &

sleep 2
if ! ps -ef | grep -q "[p]ort-forward .* ${DEFAULT_GRAFANA_PORT}:80 .* ${NAMESPACE}"; then
  echo "[Prometheus] Binding to ${VM_IP} failed; falling back to 0.0.0.0"
  kubectl port-forward svc/prometheus-grafana -n "${NAMESPACE}" \
      "${DEFAULT_GRAFANA_PORT}:80" --address 0.0.0.0 >/tmp/grafana-portforward.log 2>&1 &
  sleep 2
fi

set -e

echo "[Prometheus] Starting port-forward for Prometheus UI..."
pkill -f "kubectl port-forward .* ${DEFAULT_PROM_PORT}:9090 -n ${NAMESPACE}" || true

set +e
kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n "${NAMESPACE}" \
    "${DEFAULT_PROM_PORT}:9090" --address "${VM_IP}" >/tmp/prom-portforward.log 2>&1 &

sleep 2
if ! ps -ef | grep -q "[p]ort-forward .* ${DEFAULT_PROM_PORT}:9090 .* ${NAMESPACE}"; then
  echo "[Prometheus] Binding to ${VM_IP} failed; falling back to 0.0.0.0"
  kubectl port-forward svc/prometheus-kube-prometheus-prometheus -n "${NAMESPACE}" \
      "${DEFAULT_PROM_PORT}:9090" --address 0.0.0.0 >/tmp/prom-portforward.log 2>&1 &
  sleep 2
fi

set -e

GRAFANA_PASS=$(kubectl get secret -n "${NAMESPACE}" prometheus-grafana \
    -o jsonpath="{.data.admin-password}" | base64 -d)

echo "========================================================"
echo " Prometheus UI:  http://${VM_IP}:${DEFAULT_PROM_PORT}"
echo " Grafana UI:     http://${VM_IP}:${DEFAULT_GRAFANA_PORT}"
echo " Grafana Login:  admin / ${GRAFANA_PASS}"
echo "========================================================"
