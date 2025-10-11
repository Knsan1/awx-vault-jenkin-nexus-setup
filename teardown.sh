#!/bin/bash
# Full teardown script with selective cleanup options
set -euo pipefail

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]
Selective teardown options for the development environment

Options:
    --awx-only          Remove only AWX components
    --vault-only        Remove only Vault namespace
    --jenkins-only      Remove only Jenkins namespace
    --artifactory-only  Remove only Artifactory namespace
    --nexus-only        Remove only Nexus namespace
    --clients-only      Remove AWX client containers and SSH keys
    --cluster-only      Remove only Kind cluster
    --clean-all         Full teardown (all components)
    --preserve-data     Keep Jenkins/Nexus volumes even in full teardown
    --help              Show this help message

Examples:
    $0 --awx-only
    $0 --artifactory-only
    $0 --nexus-only
    $0 --clean-all
    $0 --clean-all --preserve-data
EOF
}

# Parse arguments
AWX_ONLY=false
VAULT_ONLY=false
JENKINS_ONLY=false
ARTIFATORY_ONLY=false
NEXUS_ONLY=false
CLIENTS_ONLY=false
CLUSTER_ONLY=false
CLEAN_ALL=false
PRESERVE_DATA=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --awx-only) AWX_ONLY=true ;;
        --vault-only) VAULT_ONLY=true ;;
        --jenkins-only) JENKINS_ONLY=true ;;
        --artifactory-only) ARTIFATORY_ONLY=true ;;
        --nexus-only) NEXUS_ONLY=true ;;
        --clients-only) CLIENTS_ONLY=true ;;
        --cluster-only) CLUSTER_ONLY=true ;;
        --clean-all) CLEAN_ALL=true ;;
        --preserve-data) PRESERVE_DATA=true ;;
        --help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done

# If no options specified, show help
if [[ "$AWX_ONLY" == false && "$VAULT_ONLY" == false && "$JENKINS_ONLY" == false && \
      "$ARTIFATORY_ONLY" == false && "$NEXUS_ONLY" == false && "$CLIENTS_ONLY" == false && \
      "$CLUSTER_ONLY" == false && "$CLEAN_ALL" == false ]]; then
    show_help
    exit 1
fi

CLUSTER_NAME="${CLUSTER_NAME:-kind}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# ----------------------------
# AWX-only teardown
# ----------------------------
if [[ "$AWX_ONLY" == true ]]; then
    print_status "Removing AWX components only..."
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        ctx="kind-${CLUSTER_NAME}"
        pkill -f "kubectl port-forward.*awx" || true
        kubectl delete awx awx-demo -n awx --ignore-not-found=true --context="$ctx" || true
        kubectl delete pvc -n awx --all --ignore-not-found=true --context="$ctx" || true
        if command -v helm &> /dev/null; then
            helm uninstall awx-operator awx -n awx --ignore-not-found 2>/dev/null || true
        fi
        kubectl delete namespace awx --ignore-not-found=true --context="$ctx" || true
        print_success "AWX components removed. Cluster and other services preserved."
    else
        print_warning "Cluster '$CLUSTER_NAME' not found"
        exit 1
    fi
fi

# ----------------------------
# Jenkins-only teardown
# ----------------------------
if [[ "$JENKINS_ONLY" == true ]]; then
    print_status "Removing Jenkins components only..."
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        ctx="kind-${CLUSTER_NAME}"
        pkill -f "kubectl port-forward.*jenkins" || true
        if command -v helm &> /dev/null; then
            helm uninstall jenkins -n jenkins --ignore-not-found 2>/dev/null || true
        fi
        kubectl delete namespace jenkins --ignore-not-found=true --context="$ctx" || true
        print_success "Jenkins components removed. Cluster and other services preserved."
    else
        print_warning "Cluster '$CLUSTER_NAME' not found"
        exit 1
    fi
fi

# ----------------------------
# Artifactory-only teardown
# ----------------------------
if [[ "$ARTIFATORY_ONLY" == true ]]; then
    print_status "Removing Artifactory components only..."
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        ctx="kind-${CLUSTER_NAME}"
        pkill -f "kubectl port-forward.*artifactory" || true
        if command -v helm &> /dev/null; then
            helm uninstall artifactory -n artifactory --ignore-not-found 2>/dev/null || true
        fi
        kubectl delete namespace artifactory --ignore-not-found=true --context="$ctx" || true
        print_success "Artifactory components removed. Cluster and other services preserved."
    else
        print_warning "Cluster '$CLUSTER_NAME' not found"
        exit 1
    fi
fi

# ----------------------------
# Nexus-only teardown
# ----------------------------
if [[ "$NEXUS_ONLY" == true ]]; then
    print_status "Removing Nexus components only..."
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        ctx="kind-${CLUSTER_NAME}"
        pkill -f "kubectl port-forward.*nexus" || true
        if command -v helm &> /dev/null; then
            helm uninstall nexus -n nexus --ignore-not-found 2>/dev/null || true
        fi
        kubectl delete namespace nexus --ignore-not-found=true --context="$ctx" || true
        print_success "Nexus components removed. Cluster and other services preserved."
    else
        print_warning "Cluster '$CLUSTER_NAME' not found"
        exit 1
    fi
fi

# ----------------------------
# Vault-only teardown
# ----------------------------
if [[ "$VAULT_ONLY" == true ]]; then
    print_status "Removing Vault namespace..."
    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        ctx="kind-${CLUSTER_NAME}"
        pkill -f "kubectl port-forward.*vault" || true
        kubectl delete namespace vault --ignore-not-found=true --context="$ctx" || true
        rm -rf vault-agent1 vault-agent2 vault-agent3 vault-server || true
        print_success "Vault namespace removed."
    else
        print_warning "Cluster '$CLUSTER_NAME' not found"
        exit 1
    fi
fi

# ----------------------------
# Client-only cleanup
# ----------------------------
if [[ "$CLIENTS_ONLY" == true ]]; then
    print_status "Removing AWX client containers..."
    for i in {1..10}; do
        docker rm -f "awx-client-${i}" 2>/dev/null || true
    done
    print_status "Cleaning up SSH keys and authorized_keys..."
    rm -f ./awx_client_key ./awx_client_key.pub || true
    rm -rf ./authorized_keys || true
    rm -rf ./nfs_share  || true
    print_success "Client cleanup completed."
fi

# ----------------------------
# Cluster-only teardown
# ----------------------------
if [[ "$CLUSTER_ONLY" == true ]]; then
    print_status "Removing Kind cluster only..."
    pkill -f "kubectl port-forward" || true
    # Remove the registry container along with the cluster
    docker rm -f registry 2>/dev/null || true
    kind delete cluster --name "$CLUSTER_NAME" || true
    print_success "Cluster removed. Other services preserved."
fi

# ----------------------------
# Full teardown
# ----------------------------
if [[ "$CLEAN_ALL" == true ]]; then
    print_status "Performing complete teardown..."
    pkill -f "kubectl port-forward" || true

    if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
        ctx="kind-${CLUSTER_NAME}"
        kubectl delete namespace awx --ignore-not-found=true --context="$ctx" || true
        kubectl delete namespace vault --ignore-not-found=true --context="$ctx" || true
        kubectl delete namespace jenkins --ignore-not-found=true --context="$ctx" || true
        kubectl delete namespace artifactory --ignore-not-found=true --context="$ctx" || true
        kubectl delete namespace nexus --ignore-not-found=true --context="$ctx" || true
    fi

    kind delete cluster --name "$CLUSTER_NAME" || true
    
    # Remove all containers, including the registry
    docker rm -f jenkins registry 2>/dev/null || true
    for i in {1..10}; do
        docker rm -f "awx-client-${i}" 2>/dev/null || true
    done

    docker network rm kindnet 2>/dev/null || true

    if [[ "$PRESERVE_DATA" == false ]]; then
        print_status "Removing Docker volumes..."
        # Explicitly remove known named volumes
        docker volume rm jenkins_home nexus_data registry_data 2>/dev/null || true
        # Prune all other unused/anonymous volumes
        docker volume prune -f 2>/dev/null || true
    else
        print_warning "Preserving data volumes (jenkins_home, nexus_data, registry_data)"
    fi

    rm -f /tmp/awx-portforward.log /tmp/vault-portforward.log /tmp/artifactory-portforward.log /tmp/nexus-portforward.log || true
    rm -f ./awx_client_key ./awx_client_key.pub || true
    rm -rf ./authorized_keys || true
    rm -rf ./nfs_share || true
    rm -rf vault-agent1 vault-agent2 vault-agent3 vault-server || true

    print_success "Complete teardown finished!"
    if [[ "$PRESERVE_DATA" == true ]]; then
        echo ""
        print_warning "Data volumes preserved:"
        docker volume ls | grep -E "(jenkins_home|nexus_data|registry_data)" || echo "No data volumes found"
    fi
fi

# ----------------------------
# Show remaining resources
# ----------------------------
echo ""
print_status "Teardown completed successfully!"

echo ""
echo "Remaining resources:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true
echo ""
echo "Kind clusters:"
kind get clusters 2>/dev/null || echo "No clusters found"
echo ""
echo "Docker volumes:"
docker volume ls --format "table {{.Name}}\t{{.Driver}}" || true
