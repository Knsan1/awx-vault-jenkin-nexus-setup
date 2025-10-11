#!/bin/bash
# Complete deployment script that orchestrates everything
set -euo pipefail

echo "======================================"
echo "Starting Complete Dev Environment Setup"
echo "======================================"

# 1. Start foundational services (e.g., local registry)
echo "[1/8] Starting Registry..."
./start_services.sh
# No sleep needed here, as the start_services.sh script should handle startup.

# 2. Create Kind cluster
echo "[2/8] Creating Kind cluster..."
./create_kind_cluster.sh
sleep 30

# 3. Install networking (Cilium + MetalLB)
echo "[3/8] Installing Cilium and MetalLB..."
./install_metallb_cilium.sh
sleep 300

# 4. Install Jenkins
echo "[4/8] Installing Jenkins..."
./deploy_jenkin.sh
# The deploy_jenkin.sh script should handle its own waiting logic.
sleep 30

# 5. Install AWX
echo "[5/8] Installing AWX..."
./install_awx.sh
# The install_awx.sh script should handle its own waiting logic.
sleep 30

# 6. Install JFrog Artifactory
echo "[6/8] Installing Nexus Repo..."
./deploy_nexus.sh
# The deploy_jfrog.sh script should handle its own waiting logic.
sleep 30

# 7. Install Vault
echo "[7/8] Installing Vault..."
./deploy_vault.sh
# The deploy_vault.sh script should handle its own waiting logic.
sleep 30

# 8. Create AWX SSH clients
echo "[8/8] Creating AWX SSH clients..."
./create_clients.sh 3

echo ""
echo "======================================"
echo "Complete environment ready!"
echo "======================================"
VM_IP=$(./detect_vm_ip.sh)
echo "Services available:"
echo "• Jenkins: http://${VM_IP}:8080"
echo "• Registry: http://${VM_IP}:5000"
echo "• AWX: http://${VM_IP}:8081"
echo "• Vault: http://${VM_IP}:18200"
echo "• Nexus: http://${VM_IP}:18081"
echo "======================================"