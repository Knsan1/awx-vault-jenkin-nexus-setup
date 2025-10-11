#!/usr/bin/env bash
set -euo pipefail

# Configuration
AWX_NS="awx"
AWX_NAME="awx"
JENKINS_NS="jenkins"
JENKINS_SVC_NAME="jenkins"
NEXUS_NS="nexus"
NEXUS_SVC_NAME="nexus"
VAULT_NS="vault"
VAULT_SVC_NAME="vault"
VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"

# Utility function to check command existence
need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}
need kubectl
need helm

echo "--- DevOps Services Status ---"
echo "========================================================"

# --- AWX Status ---
echo "--- AWX Status ---"
if kubectl get pods -n "${AWX_NS}" -l "app.kubernetes.io/name=${AWX_NAME}" &>/dev/null; then
  echo "AWX is running in Kubernetes namespace: ${AWX_NS}."
  echo "--- AWX Pods ---"
  kubectl get pods -n "${AWX_NS}" -o wide
  echo "--- AWX Services ---"
  kubectl get svc -n "${AWX_NS}"
else
  echo "No AWX instance found running in the Kubernetes namespace: ${AWX_NS}."
fi

echo "========================================================"

# --- Jenkins Status ---
echo "--- Jenkins Status ---"
if kubectl get pods -n "${JENKINS_NS}" -l "app.kubernetes.io/name=${JENKINS_SVC_NAME}" &>/dev/null; then
  echo "Jenkins is running on Kubernetes in namespace: ${JENKINS_NS}."
  echo "--- Jenkins Pods ---"
  kubectl get pods -n "${JENKINS_NS}" -o wide
  echo "--- Jenkins Services ---"
  kubectl get svc -n "${JENKINS_NS}"
else
  echo "No Jenkins instance found running in the Kubernetes namespace: ${JENKINS_NS}."
fi

echo "========================================================"

# --- Nexus Status ---
echo "--- Nexus Status ---"
if kubectl get pods -n "${NEXUS_NS}" -l "app.kubernetes.io/name=${NEXUS_SVC_NAME}" &>/dev/null; then
  echo "Nexus is running in Kubernetes namespace: ${NEXUS_NS}."
  echo "--- Nexus Pods ---"
  kubectl get pods -n "${NEXUS_NS}" -o wide
  echo "--- Nexus Services ---"
  kubectl get svc -n "${NEXUS_NS}"
else
  echo "No Nexus instance found running in the Kubernetes namespace: ${NEXUS_NS}."
fi

echo "========================================================"

# --- Vault Status ---
echo "--- Vault Status ---"
if kubectl get pods -n "${VAULT_NS}" -l "app.kubernetes.io/name=${VAULT_SVC_NAME}" &>/dev/null; then
  echo "Vault is running in Kubernetes namespace: ${VAULT_NS}."
  echo "--- Vault Pods ---"
  kubectl get pods -n "${VAULT_NS}" -o wide
  echo "--- Vault Services ---"
  kubectl get svc -n "${VAULT_NS}"
else
  echo "No Vault instance found running in the Kubernetes namespace: ${VAULT_NS}."
fi

echo "========================================================"

# --- Service Credentials ---
echo "--- Service Credentials ---"
echo "========================================================"

# AWX Credentials
echo "• AWX URL: http://${VM_IP}:8081"
if kubectl get secret "${AWX_NAME}-admin-password" -n "${AWX_NS}" &>/dev/null; then
  echo "  - Admin Password:"
  kubectl get secret "${AWX_NAME}-admin-password" -n "${AWX_NS}" -o jsonpath='{.data.password}' | base64 --decode
  echo ""
else
  echo "  - Admin Password: Not found"
fi

# Jenkins Credentials
echo "• Jenkins URL: http://${VM_IP}:8080"
if kubectl get secret -n "${JENKINS_NS}" "${JENKINS_SVC_NAME}" &>/dev/null; then
  echo "  - Admin Password:"
  kubectl get secret -n "${JENKINS_NS}" "${JENKINS_SVC_NAME}" -o jsonpath="{.data.jenkins-admin-password}" | base64 --decode
  echo ""
else
  echo "  - Admin Password: Not found"
fi

# Vault Credentials
echo "• Vault URL: http://${VM_IP}:18200"
# if kubectl get secret -n "${VAULT_NS}" vault-unseal-keys &>/dev/null; then
#   echo "  - Initial Root Token:"
#   kubectl get secret -n "${VAULT_NS}" vault-unseal-keys -o jsonpath='{.data.root-token}' | base64 --decode
#   echo ""
# else
  echo "  - Initial Root Token: root"
# fi

# Nexus Credentials
echo "• Nexus URL: http://${VM_IP}:18081"
echo "  - Admin User: admin"
if kubectl get secret -n "${NEXUS_NS}" "${NEXUS_SVC_NAME}-nexus-repository-manager" &>/dev/null; then
  echo "  - Initial Admin Password:"
  kubectl get secret -n "${NEXUS_NS}" "${NEXUS_SVC_NAME}-nexus-repository-manager" -o jsonpath="{.data.nexus-admin-password}" | base64 --decode
  echo ""
else
  ADMIN_PASS=$(kubectl exec -it deploy/${NEXUS_SVC_NAME}-nexus-repository-manager -n "${NEXUS_NS}" -- cat /nexus-data/admin.password 2>/dev/null | tr -d '\r')
  if [ -n "${ADMIN_PASS}" ]; then
    echo "  - Initial Admin Password: ${ADMIN_PASS}"
  else
    echo "  - Initial Admin Password: Not found"
  fi
fi
