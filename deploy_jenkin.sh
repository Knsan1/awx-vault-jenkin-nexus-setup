#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="jenkins"
DEFAULT_JENKINS_PORT=8080
DEFAULT_AGENT_PORT=50000

JENKINS_CHART_VERSION="5.8.110" 

VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }
need kubectl
need helm

echo "[Jenkins] Using VM IP: ${VM_IP}"
echo "[Jenkins] Forward ports: ${DEFAULT_JENKINS_PORT} (web) and ${DEFAULT_AGENT_PORT} (agent)"

echo "[Jenkins] Create namespace..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "[Jenkins] Add Helm repo..."
helm repo add jenkins https://charts.jenkins.io || true
helm repo update

echo "[Jenkins] Install Jenkins via Helm..."
helm upgrade --install jenkins jenkins/jenkins \
  --namespace "${NAMESPACE}" \
  --version "$JENKINS_CHART_VERSION" \
  --set controller.serviceType=ClusterIP \
  --set controller.jenkinsUrl="http://${VM_IP}:${DEFAULT_JENKINS_PORT}" \
  --wait --timeout 15m


echo "[Jenkins] Checking pod readiness..."
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/component=jenkins-controller" -n "${NAMESPACE}" --timeout=15m
echo "[Jenkins] Pod is ready"

# Get the Jenkins controller pod name
JENKINS_POD=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/component=jenkins-controller -o jsonpath="{.items[0].metadata.name}")

echo "[Jenkins] Disabling security in config.xml..."
kubectl exec -n "${NAMESPACE}" $JENKINS_POD -- /bin/sh -c "sed -i.bak -e 's/<useSecurity>true<\/useSecurity>/<useSecurity>false<\/useSecurity>/g' \
  -e '/<securityRealm/,/<\/securityRealm>/d' -e '/<authorizationStrategy/,/<\/authorizationStrategy>/d' /var/jenkins_home/config.xml"

echo "[Jenkins] Restarting pod to apply config changes..."
kubectl delete pod -n "${NAMESPACE}" $JENKINS_POD

echo "[Jenkins] Waiting for pod to be ready again..."
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/component=jenkins-controller" -n "${NAMESPACE}" --timeout=15m

echo "[Jenkins] Security disabled and pod is ready."

pkill -f "kubectl port-forward svc/jenkins.*${NAMESPACE}" || true

echo "[Jenkins] Port-forward ${VM_IP}:${DEFAULT_JENKINS_PORT} -> 8080..."
kubectl port-forward svc/jenkins -n "${NAMESPACE}" "${DEFAULT_JENKINS_PORT}:8080" --address "${VM_IP}" >/tmp/jenkins-web-portforward.log 2>&1 &
PF_WEB_PID=$!
sleep 2
if ! ps -p "${PF_WEB_PID}" > /dev/null; then
  echo "[Jenkins] Binding to ${VM_IP} failed for web service; falling back to 0.0.0.0"
  kubectl port-forward svc/jenkins -n "${NAMESPACE}" "${DEFAULT_JENKINS_PORT}:8080" --address 0.0.0.0 >/tmp/jenkins-web-portforward.log 2>&1 &
fi

echo "[Jenkins] Port-forward ${VM_IP}:${DEFAULT_AGENT_PORT} -> 50000..."
kubectl port-forward svc/jenkins-agent -n "${NAMESPACE}" "${DEFAULT_AGENT_PORT}:50000" --address "${VM_IP}" >/tmp/jenkins-agent-portforward.log 2>&1 &
PF_AGENT_PID=$!
sleep 2
if ! ps -p "${PF_AGENT_PID}" > /dev/null; then
  echo "[Jenkins] Binding to ${VM_IP} failed for agent service; falling back to 0.0.0.0"
  kubectl port-forward svc/jenkins-agent -n "${NAMESPACE}" "${DEFAULT_AGENT_PORT}:50000" --address 0.0.0.0 >/tmp/jenkins-agent-portforward.log 2>&1 &
fi

echo "[Jenkins] Retrieving initial admin password from k8s secret..."
# Get the base64 encoded password from the secret and decode it
initial_password=$(kubectl get secret -n "${NAMESPACE}" jenkins -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode)

echo "========================================================"
echo " Jenkins URL: http://${VM_IP}:${DEFAULT_JENKINS_PORT}"
echo " Jenkins Agent URL: http://${VM_IP}:${DEFAULT_AGENT_PORT}"
echo " Initial Admin Password:"
echo " ${initial_password}"
echo "========================================================"
