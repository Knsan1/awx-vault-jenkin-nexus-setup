#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="awx"
RELEASE_NAME="awx"
DEFAULT_HOST_PORT=8081

AWX_OPERATOR_CHART_VERSION="3.2.0" 

# Detect VM IP
VM_IP=$(./detect_vm_ip.sh || echo "127.0.0.1")
echo "Using VM IP: $VM_IP"

# Function: check if namespace exists
create_namespace() {
  echo "[Step 1] Ensure namespace exists..."
  kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl create ns $NAMESPACE
}

# Function: install AWX operator
install_operator() {
  echo "[Step 2] Add Helm repo..."
  helm repo add awx-operator https://ansible-community.github.io/awx-operator-helm/ || true
  helm repo update

  echo "[Step 3] Install AWX Operator via Helm..."
  helm upgrade --install awx-operator awx-operator/awx-operator \
    --namespace $NAMESPACE \
    --version "$AWX_OPERATOR_CHART_VERSION" \
    --set serviceAccount.name=awx-operator
}

# Function: deploy AWX instance
deploy_awx() {
  echo "[Step 4] Deploy AWX instance..."
  cat <<EOF | kubectl apply -f -
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: $RELEASE_NAME
  namespace: $NAMESPACE
spec:
  service_type: NodePort
  ingress_type: none
  nodeport_port: 30080
  postgres_storage_class: standard
  postgres_storage_requirements:
    requests:
      storage: 8Gi
  admin_user: admin
  admin_password_secret: ${RELEASE_NAME}-admin-password
EOF
}

# Function: wait for pods to be ready
wait_for_pods() {
  echo "[Step 5] Wait for all AWX pods to be Ready..."
  TIMEOUT=1200   # 20 minutes
  INTERVAL=15
  ELAPSED=0

  while [ $ELAPSED -lt $TIMEOUT ]; do
    pods_status=$(kubectl get pods -n $NAMESPACE --no-headers)

    all_ready=true
    echo "Pods status snapshot:"
    echo "$pods_status"

    while read -r line; do
      name=$(echo "$line" | awk '{print $1}')
      ready=$(echo "$line" | awk '{print $2}')
      status=$(echo "$line" | awk '{print $3}')

      # ready looks like "3/3", check if equal
      if [[ "$ready" != "$(echo $ready | cut -d'/' -f2)/$(echo $ready | cut -d'/' -f2)" ]]; then
        all_ready=false
      fi
      if [[ "$status" != "Running" && "$status" != "Completed" ]]; then
        all_ready=false
      fi
    done <<< "$pods_status"

    if [ "$all_ready" = true ]; then
      echo "✓ All AWX pods are Ready or Completed!"
      return
    else
      echo "Waiting for pods to be ready..."
      sleep $INTERVAL
      ELAPSED=$((ELAPSED + INTERVAL))
    fi
  done

  echo "⚠ Timeout reached. Some AWX pods are not ready yet."
  kubectl get pods -n $NAMESPACE
}


# Function: setup port-forward
setup_portforward() {
  echo "[Step 6] Waiting for AWX service '${RELEASE_NAME}-service' to be ready..."

  # Wait for service + endpoints
  for i in {1..30}; do
    if kubectl get svc "${RELEASE_NAME}-service" -n "$NAMESPACE" &>/dev/null; then
      ENDPOINTS=$(kubectl get endpoints "${RELEASE_NAME}-service" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
      [ -n "$ENDPOINTS" ] && break
    fi
    echo "Waiting for AWX service endpoints..."
    sleep 5
  done

  if [ -z "$ENDPOINTS" ]; then
    echo "ERROR: AWX service not ready. Cannot port-forward."
    exit 1
  fi

  echo "AWX service ready. Port-forwarding on ${VM_IP}:${DEFAULT_HOST_PORT}..."
  pkill -f "kubectl port-forward svc/${RELEASE_NAME}-service" || true
  nohup kubectl port-forward svc/"${RELEASE_NAME}-service" \
    -n "$NAMESPACE" ${DEFAULT_HOST_PORT}:80 --address "$VM_IP" \
    > /tmp/awx-portforward.log 2>&1 &
  echo "Port-forward started. Logs: /tmp/awx-portforward.log"
}



# Run steps
create_namespace
install_operator
deploy_awx
wait_for_pods
setup_portforward

# Show info
echo "========================================================"
echo " AWX should now be accessible at: http://${VM_IP}:${DEFAULT_HOST_PORT}"
echo " Default admin user: admin"
echo " Get password with:"
echo "   kubectl get secret ${RELEASE_NAME}-admin-password -n $NAMESPACE -o jsonpath='{.data.password}' | base64 --decode"
echo "========================================================"
