# 🚀 AWX + HashiCorp Vault Setup

This repository contains automation scripts to deploy and manage a self-contained **AWX** instance integrated with **HashiCorp Vault** within a local Kubernetes environment created by **KinD** (Kubernetes in Docker).

The setup is designed for testing and learning purposes, providing a complete, ready-to-use development environment for working with AWX and Vault secrets management.

---

## 📂 Project Structure

```

awx-vault-setup/
├── configure\_awx.sh        \# Configures AWX with Vault and SSH credentials
├── create\_clients.sh       \# Creates Docker containers to act as SSH clients
├── create\_kind\_cluster.sh  \# Creates a local KinD (Kubernetes in Docker) cluster
├── deploy\_vault.sh         \# Deploys HashiCorp Vault in Kubernetes (dev mode)
├── detect\_vm\_ip.sh         \# Detects the VM or host IP address for service exposure
├── infra\_setup.sh          \# Master script to run a full setup of all services
├── install\_awx.sh          \# Deploys AWX using the AWX Operator
├── install\_metallb\_cilium.sh \# Installs a CNI (Cilium) and LoadBalancer (MetalLB)
├── start\_services.sh       \# Starts Jenkins and a local Docker registry
├── status\_awx.sh           \# Displays AWX pod, service, and login information
└── teardown.sh             \# Comprehensive script for cleaning up resources

````

---

## 🛠️ Prerequisites

Make sure you have the following tools installed and accessible in your PATH:

-   **[Docker](https://docs.docker.com/get-docker/)**
-   **[KinD](https://kind.sigs.k8s.io/)**
-   **[kubectl](https://kubernetes.io/docs/tasks/tools/)**
-   **[Helm](https://helm.sh/docs/intro/install/)**
-   **[jq](https://stedolan.github.io/jq/)**
-   **[curl](https://curl.se/)**
-   **[ssh-keygen](https://man.openbsd.org/ssh-keygen.1)** (part of OpenSSH)
-   **[python3](https://www.python.org/downloads/)**
-   **[Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)** (Required for testing the AWX inventory)
-   A modern Linux system (tested on Ubuntu / RHEL / AIX)

---

## ⚡ Quickstart: All-in-One Setup

The simplest way to get started is by using the master setup script, which automates most of the steps.

```bash
# Set up the AWX clients, Kind cluster, networking, and AWX instance.
./infra_setup.sh

# Deploy Vault separately as it's not included in the main setup script.
./deploy_vault.sh

# Configure AWX to connect to Vault and the SSH clients.
./configure_awx.sh
````

-----

## 📄 Manual Setup Walkthrough

If you prefer to run each step individually, follow this sequence:

### 1\. Start Services & Create Kubernetes Cluster

This step creates a shared Docker network, starts a Jenkins and a Docker registry container, and then creates the Kind cluster.

```bash
# Start external services (Jenkins, Registry)
./start_services.sh

# Create the KinD cluster
./create_kind_cluster.sh

# Install networking components (Cilium CNI and MetalLB LoadBalancer)
./install_metallb_cilium.sh
```

### 2\. Deploy Vault & AWX

These scripts deploy Vault and AWX into their respective namespaces within the KinD cluster.

```bash
# Deploy Vault in "dev" mode
./deploy_vault.sh

# Deploy the AWX Operator and an AWX instance
./install_awx.sh
```

### 3\. Configure Clients & AWX

This sets up the SSH clients for AWX to manage and configures AWX with the necessary credentials.

```bash
# Create client containers and an SSH keypair
./create_clients.sh

# Configure AWX with SSH and Vault credentials
./configure_awx.sh
```

-----

## 🔍 Status & Services

### Check AWX

Get the AWX admin password and view the status of its pods and services.

```bash
./status_awx.sh
```

### Get VM/Host IP

This is useful if you are running the setup inside a VM.

```bash
./detect_vm_ip.sh
```

-----

## 🧹 Teardown

The `teardown.sh` script provides a **comprehensive and selective** cleanup utility.

```bash
# Full teardown of all components (cluster, services, clients)
./teardown.sh --clean-all

# Or, use selective options:
./teardown.sh --awx-only      # Remove only AWX
./teardown.sh --vault-only    # Remove only Vault
./teardown.sh --cluster-only  # Remove only the Kind cluster
./teardown.sh --clients-only  # Remove only the Docker clients
./teardown.sh --services-only # Remove only Jenkins and Registry
./teardown.sh --help          # See all available options
```

-----

## 🛡️ Troubleshooting

### Pods Stuck in Pending/Creating

If pods are not starting, check the networking. Ensure that Cilium and MetalLB are running correctly.

```bash
# Check Cilium status
kubectl get pods -n kube-system -l k8s-app=cilium

# Check MetalLB status
kubectl get pods -n metallb-system
```

### AWX Login

The `status_awx.sh` script provides the command to retrieve the admin password.

```bash
kubectl get secret -n awx awx-admin-password -o jsonpath="{.data.password}" | base64 --decode; echo
```

-----

## ✅ Notes

  * This setup is **for demo and learning** purposes only and is not production-ready.
  * Ensure you have at least **4GB+ of memory** available for the Docker/KinD cluster.
  * All scripts should be executed from the repository root directory.
  * The setup may take several minutes to complete, as it waits for various Kubernetes resources to become ready.

-----

## 📜 License

MIT License – free to use and modify.

```