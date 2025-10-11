#!/usr/bin/env bash
# Script to manage kubectl port-forwarding with IP fallback logic.
# Uses environment variables defined in your service status checker script for consistency.

# Ensure script exits immediately if a command exits with a non-zero status
set -euo pipefail

# --- Configuration Variables ---
# These variables should be set externally or sourced from your environment.
# Providing defaults for robustness.
AWX_NS="${AWX_NS:-awx}"
AWX_NAME="${AWX_NAME:-awx}"
JENKINS_NS="${JENKINS_NS:-jenkins}"
JENKINS_SVC_NAME="${JENKINS_SVC_NAME:-jenkins}"
NEXUS_NS="${NEXUS_NS:-nexus}"
NEXUS_SVC_NAME="${NEXUS_SVC_NAME:-nexus}"
VAULT_NS="${VAULT_NS:-vault}"
VAULT_SVC_NAME="${VAULT_SVC_NAME:-vault}"
VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"

# Define default host ports based on your access pattern (ports forwarded to the host machine)
VAULT_HOST_PORT="18200"        # Host port for Vault UI (Target 8200)
NEXUS_HOST_PORT="18081"        # Host port for Nexus UI (Target 8081)
AWX_HOST_PORT="8081"           # Host port for AWX UI (Target 80)
JENKINS_HOST_PORT="8080"       # Host port for Jenkins UI (Target 8080)
JENKINS_AGENT_PORT="50000"     # Target port inside Jenkins agent pod
JENKINS_AGENT_HOST_PORT="15000" # Host port for Jenkins Agent (Target 50000)
# --------------------------------------------------------


# Function to handle port-forwarding with automatic IP fallback
# Arguments:
# 1: Log prefix (e.g., "[Vault]", "[Nexus]")
# 2: Service name (e.g., "svc/vault", "svc/nexus-repository-manager")
# 3: Namespace
# 4: Target port (The container/service port, e.g., 8200)
# 5: Local port (The host port, e.g., 18200)
run_port_forward_with_fallback() {
    local LOG_PREFIX="$1"
    local SERVICE="$2"
    local NAMESPACE="$3"
    local TARGET_PORT="$4"
    local LOCAL_PORT="$5"
    # Create a unique log file path based on service and port
    local LOG_FILE="/tmp/$(echo "$SERVICE" | tr '/' '-')"-"${LOCAL_PORT}-portforward.log"
    local SERVICE_PID=0

    echo "${LOG_PREFIX} Checking/Stopping old process on port ${LOCAL_PORT}..."
    # Kill any existing process using this specific port forward pattern
    pkill -f "kubectl port-forward ${SERVICE} -n ${NAMESPACE} ${LOCAL_PORT}:${TARGET_PORT}" 2>/dev/null || true

    echo "${LOG_PREFIX} Attempting port-forward on ${VM_IP}:${LOCAL_PORT} -> ${TARGET_PORT}"

    # Use 'set +e' temporarily to allow background command failure
    set +e
    
    # Attempt 1: Bind to the specific VM_IP
    kubectl port-forward "$SERVICE" -n "${NAMESPACE}" "${LOCAL_PORT}:${TARGET_PORT}" \
        --address "${VM_IP}" >"${LOG_FILE}" 2>&1 &
    SERVICE_PID=$!
    
    # Wait briefly and check if the process is still running
    sleep 2
    if ! ps -p "${SERVICE_PID}" > /dev/null; then
        echo "${LOG_PREFIX} Binding to ${VM_IP} failed; attempting fallback to 0.0.0.0..."
        
        # Kill the failed process (if it exists)
        kill "${SERVICE_PID}" 2>/dev/null || true
        
        # Attempt 2: Fallback to bind to all interfaces (0.0.0.0)
        kubectl port-forward "$SERVICE" -n "${NAMESPACE}" "${LOCAL_PORT}:${TARGET_PORT}" \
            --address 0.0.0.0 >"${LOG_FILE}" 2>&1 &
        SERVICE_PID=$!
        sleep 2
        
        # Final check for fallback status
        if ! ps -p "${SERVICE_PID}" > /dev/null; then
             echo "${LOG_PREFIX} ERROR: Port-forward failed for both ${VM_IP} and 0.0.0.0. Check service status: kubectl get svc -n ${NAMESPACE}"
             return 1
        fi
    fi
    
    # Restore error handling
    set -e
    echo "${LOG_PREFIX} Port-forward successful on port ${LOCAL_PORT} (PID: ${SERVICE_PID}). Logs: ${LOG_FILE}"
    return 0
}

# --- Service Execution ---

echo "Starting Port Forwards..."

# 1. Vault Service (Target 8200)
run_port_forward_with_fallback \
    "[Vault]" \
    "svc/${VAULT_SVC_NAME}" \
    "${VAULT_NS}" \
    "8200" \
    "${VAULT_HOST_PORT}"

# 2. Nexus Service (Target 8081)
# Note: Using svc/${NEXUS_SVC_NAME}-nexus-repository-manager as derived from your original script
run_port_forward_with_fallback \
    "[Nexus]" \
    "svc/${NEXUS_SVC_NAME}-nexus-repository-manager" \
    "${NEXUS_NS}" \
    "8081" \
    "${NEXUS_HOST_PORT}"

# 3. AWX Service (Target 80)
run_port_forward_with_fallback \
    "[AWX]" \
    "svc/${AWX_NAME}-service" \
    "${AWX_NS}" \
    "80" \
    "${AWX_HOST_PORT}"

# 4. Jenkins UI Service (Target 8080)
run_port_forward_with_fallback \
    "[Jenkins UI]" \
    "svc/${JENKINS_SVC_NAME}" \
    "${JENKINS_NS}" \
    "8080" \
    "${JENKINS_HOST_PORT}"

# 5. Jenkins Agent Service (Target 50000)
run_port_forward_with_fallback \
    "[Jenkins Agent]" \
    "svc/${JENKINS_SVC_NAME}-agent" \
    "${JENKINS_NS}" \
    "${JENKINS_AGENT_PORT}" \
    "${JENKINS_AGENT_HOST_PORT}"

echo "========================================================"
echo "All primary services port-forwarded successfully."
echo "Access URLs on VM_IP: ${VM_IP}"
echo "========================================================"
