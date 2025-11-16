# 🚀 AWX + HashiCorp Vault + Jenkins + Nexus Setup on Kind Kubernetes

[![GitHub Repo stars](https://img.shields.io/github/stars/Knsan1/awx-vault-jenkin-nexus-setup?style=social)](https://github.com/Knsan1/awx-vault-jenkin-nexus-setup)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

This repository provides automation scripts to deploy a complete development environment for **AWX** (Ansible Automation Platform), **HashiCorp Vault** (secrets management), **Jenkins** (CI/CD), and **Nexus** (artifact repository, implemented as a local Docker registry) on a local **Kind** (Kubernetes in Docker) cluster. The setup integrates AWX with Vault for secure secrets handling, includes Jenkins for pipelines, and SSH clients for testing automation workflows.

**Purpose**: Ideal for learning, testing, and development. **Not for production**—Vault is in dev mode (insecure), and the setup lacks persistence/TLS.

---

## Table of Contents
1. [What You'll Get](#what-youll-get)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start-full-setup)
4. [Detailed Setup Steps](#detailed-setup-steps)
   - [Start External Services](#1-start-external-services-jenkins-nexusregistry)
   - [Create Kind Cluster](#2-create-kind-kubernetes-cluster)
   - [Install Networking](#3-install-networking-cilium--metallb)
   - [Deploy AWX](#4-deploy-awx)
   - [Deploy Vault](#5-deploy-vault)
   - [Create SSH Clients](#6-create-ssh-clients)
   - [Configure AWX with Vault & Job Templates](#7-configure-awx-with-vault--job-templates)
   - [Detect & Replace IP for Access](#8-detect--replace-ip-for-access)
5. [Teardown & Cleanup](#teardown--cleanup)
6. [Troubleshooting](#troubleshooting)
7. [Explanation & Architecture](#explanation--architecture)
8. [Security Notes](#security-notes)
9. [Contributing & License](#contributing--license)
10. [Support](#support)

---

## 🎯 What You'll Get

- **Kind Kubernetes Cluster** – Local K8s with Cilium CNI and MetalLB for LoadBalancer services.
- **AWX** – Deployed via AWX Operator, configured with Vault integration, credentials, inventory, and sample job templates.
- **Vault** – In dev mode for quick secrets management (root token: `root`).
- **Jenkins** – Running on port `8080` for CI/CD pipelines.
- **Nexus** – Implemented as a local Docker registry on port `18081` (`admin` / `admin123`).
- **SSH Clients** – Containers (`client-1`, `client-2`, `client-3`) for AWX job testing.
- **Local Docker Registry** – Integrated with Jenkins and AWX for pushing/pulling images.

---

## 📋 Prerequisites

- **Docker**: v20+
- **Kubernetes CLI (kubectl)**: v1.25+
- **Helm**: v3.8+
- **Kind**: v0.20+
- **System Resources**: ≥ 8GB RAM, 4 CPU cores
- **OS**: Linux/macOS (tested on Ubuntu 22.04)

### Install Tools

```bash
# Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### Clone Repository

```bash
git clone https://github.com/Knsan1/awx-vault-jenkin-nexus-setup.git
cd awx-vault-jenkin-nexus-setup
chmod +x *.sh
```

---

## ⚡ Quick Start: Full Setup

Run the master script for full deployment (10–15 minutes):

```bash
./infra_setup.sh      # Sets up cluster, networking, services, AWX, clients
./configure_awx.sh    # Configures AWX with Vault, credentials, inventory
./configure_vault.sh  # Configure Vault Secret Engine and Role
./create_awx_job_templates.sh   ## Create Job Templates on the AWS mapping with Repo
./status_awx_jenkin_vault_nexus/sh  ## Checking Status of export service and URL with Password
./port-forward-only.sh   ## In case portforwarding is not working properly run this to portforward again
```

Access services (replace `<IP>` from `./detect_vm_ip.sh`):

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| **AWX** | `http://<IP>:8081` | password from `./status_awx.sh` |
| **Vault** | `http://<IP>:18200` | token: `root` |
| **Jenkins** | `http://<IP>:8080` | `admin123` |
| **Nexus/Registry** | `http://<IP>:18081` | `admin` / `admin123` |

---

## 📖 Detailed Setup Steps

Follow these scripts for granular control or troubleshooting. Each script is self-contained and waits for readiness.

### 1) Start External Services (Jenkins, Nexus/Registry)

```bash
./start_services.sh
```

**What it does**: Creates a shared Docker network, starts Jenkins (port 8080) and a local Docker registry (port 5000, acting as Nexus for artifact storage).

**Output**: Services running in Docker; check with `docker ps`.

---

### 2) Create Kind Kubernetes Cluster

```bash
./create_kind_cluster.sh
```

**What it does**: Creates a multi-node Kind cluster (1 control-plane, 1 worker).

**Output**: Cluster ready; verify with `kubectl get nodes`.

---

### 3) Install Networking (Cilium CNI & MetalLB)

```bash
./install_metallb_cilium.sh
```

**What it does**: Installs Cilium for pod networking and MetalLB for LoadBalancer IPs (pool: 192.168.65.240-255).

**Output**: Pods in `kube-system` and `metallb-system`; check with `kubectl get pods -n kube-system` and `kubectl get pods -n metallb-system`.

---

### 4) Deploy AWX

```bash
./install_awx.sh
```

**What it does**: Adds Helm repo, installs AWX Operator, and creates an AWX instance in the `awx` namespace.

**Output**: AWX pods running; check with `./status_awx.sh`.

---

### 5) Deploy Vault

```bash
./deploy_vault.sh
```

**What it does**: Adds Helm repo, deploys Vault in dev mode (`vault` namespace), and sets up port-forwarding to port 18200.

**Output**: Vault pod ready; access at `http://<IP>:18200` (token: `root`). If port-forward fails, see troubleshooting.

---

### 6) Create SSH Clients

```bash
./create_clients.sh
```

**What it does**: Creates 3 Docker containers (`client-1/2/3`) with SSH enabled (ports 2222/2223/2224) and generates a keypair for AWX access.

**Output**: Containers running; test SSH: `ssh root@<IP> -p 2222`.

---

### 7) Configure AWX with Vault & Job Templates

```bash
./configure_awx.sh
```

**What it does**: Configures AWX to integrate with Vault (as credential backend), adds SSH credentials/inventory for clients, and creates sample job templates (e.g., for running playbooks on clients using Vault secrets).

**Output**: AWX ready for jobs; login via `./status_awx.sh` and check the UI for templates.

---

### 8) Detect & Replace IP for Access

If running in a VM/cloud (e.g., port-forward issues):

```bash
./detect_vm_ip.sh  # Outputs your VM/host IP (e.g., 192.168.65.131)
```

**Manual Port Forward (if MetalLB fails)**: Replace `<IP>` with your IP in URLs. For Vault/AWX:

```bash
kubectl port-forward svc/vault -n vault 18200:8200 --address <your-IP>
kubectl port-forward svc/awx-service -n awx 8081:8052 --address <your-IP>
```

---

## 🧹 Teardown & Cleanup

Use selective or full cleanup:

```bash
./teardown.sh --clean-all  # Removes cluster, services, clients, AWX, Vault
```

**Options**:

- `--awx-only`: Remove AWX.
- `--vault-only`: Remove Vault.
- `--cluster-only`: Remove Kind cluster.
- `--clients-only`: Remove SSH clients.
- `--services-only`: Stop Jenkins/Nexus/registry.
- `--help`: Full list.

**Manual Cleanup**:

```bash
kind delete cluster --name <cluster-name>
docker rm -f $(docker ps -q -f name=client-*)
```

---

## 🔍 Troubleshooting

### Common Issues

- **Pods Stuck in Pending**: Networking issue. Fix: `./install_metallb_cilium.sh`. Check: `kubectl get pods -n kube-system -l k8s-app=cilium` and `kubectl get pods -n metallb-system`.
- **AWX/Vault Unreachable**: Port-forward failure. Fix: Run `./detect_vm_ip.sh` to get IP, then manually forward (see step 8). Check service IPs: `kubectl get svc -A`.
- **SSH Clients Connection Fails**: Keypair mismatch. Fix: `./create_clients.sh` to regenerate. Test: `ssh root@<IP> -p 2222 -i <keyfile>`.
- **Job Templates Not Created**: Configuration failure. Fix: `./configure_awx.sh`. Check AWX UI for projects/credentials/inventory.
- **Resource Errors**: Low RAM. Fix: Allocate 8GB+; monitor `docker stats`.
- **IP Replacement Issues**: In VM, localhost doesn't work externally. Fix: Use `./detect_vm_ip.sh` and replace in URLs/port-forwards.

### Debug Tools

- Logs: `kubectl logs -n awx <awx-pod>`, `kubectl logs -n vault <vault-pod>`.
- Events: `kubectl get events --sort-by='.lastTimestamp'`.
- Services: `kubectl get svc --all-namespaces`.
- Docker: `docker logs jenkins` or `docker logs registry`.
- Kind: `kind get clusters`, `kubectl cluster-info`.

If stuck, open an issue with logs/output.

---

## 📚 Explanation & Architecture

### Workflow

1. External services (Jenkins/Nexus/registry) start for CI/CD and image storage.
2. Kind cluster created with Cilium/MetalLB for networking and service exposure.
3. AWX and Vault deployed in separate namespaces.
4. SSH clients created for AWX testing.
5. AWX configured with Vault (for secrets) and job templates (e.g., Ansible playbooks).

### Integration

- **AWX + Vault**: AWX fetches secrets from Vault for jobs.
- **AWX + Clients**: Job templates use SSH inventory to run on clients.
- **Jenkins + Nexus**: Jenkins pipelines can push to registry; integrate with AWX via hooks.
- **Port Forwarding**: MetalLB exposes services; manual forward if issues.

### Diagram

```
[Host/VM (192.168.65.131)] ## IP will be different depend on each user VM Host IP
├── Docker (External)
│   └── Clients (2222-2224)
└── Kind Cluster
    ├── Cilium + MetalLB
    ├── AWX (awx ns, 8081)
    ├── Vault (vault ns, 18200)
    ├── Jenkins (8080)
    └── Nexus/Registry (5000/18081)
```

### Deploy Prometheus (Extra Step)

You can deploy extra Prometheus with a single command by running the deployment script:

```bash
./deploy_prometheus.sh
```

This script will:

1. Create the `monitoring` namespace.
2. Install Prometheus and Grafana using Helm with your custom `prometheus-values.yml`.
3. Set up access via NodePort or port-forwarding for Grafana and Prometheus dashboards.

**Verify deployment:**

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

**Cleanup (if needed):**

```bash
./clean_prometheus.sh
```

---

## 🔒 Security Notes

- Dev mode Vault: No encryption/TLS; secrets lost on restart.
- Credentials: Change defaults (`admin123` for Jenkins/Nexus).
- Exposure: Use firewall to restrict ports.

---

## 🤝 Contributing

Fork, PR, and open issues for improvements.

---

## 📜 License

MIT License. See [LICENSE](LICENSE).

---

## 📞 Support

- Issues: GitHub.
- Questions: Check troubleshooting first.

---

*Last Updated: October 2025*  
*Built for Ansible and K8s enthusiasts*
