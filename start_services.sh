#!/bin/bash
# Starts Jenkins and Docker registry on a shared network accessible to kind clusters

set -euo pipefail

VM_IP=$(./detect_vm_ip.sh)

# Create shared network for kind and other containers
docker network create kindnet || true

# Start registry
docker run -d --restart=always --name registry --network kindnet \
  -p "${VM_IP}:5000:5000" registry:2

# # Start Jenkins (simplified, can pre-install plugins later)
# docker run -d --restart=always --name jenkins --network kindnet \
#   -p "${VM_IP}:8080:8080" -p "${VM_IP}:50000:50000" \
#   -v jenkins_home:/var/jenkins_home \
#   jenkins/jenkins:lts
