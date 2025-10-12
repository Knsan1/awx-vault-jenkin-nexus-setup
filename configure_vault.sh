#!/bin/bash

# A simple script to put data, create policies, and enable the AppRole auth method in Vault.
# This script assumes you have direct access to the Vault CLI.
VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"

# --- Set Vault Address and Token ---
export VAULT_ADDR="http://${VM_IP}:18200"
export VAULT_TOKEN='root'


# --- Function to generate a random URL ---
generate_random_url() {
  head /dev/urandom | tr -dc A-Za-z0-9 | head -c 10
  echo ".com"
}

# --- Function to generate a random password ---
generate_random_password() {
  head /dev/urandom | tr -dc A-Za-z0-9\-\_ | head -c 12
}

# --- Set variables for users, customers, and data paths ---
declare -a users=("user1" "user2" "user3")
declare -a customer_names=("acme" "techcorp" "retailx")
declare -a file_paths=("data1.json" "data2.json" "data3.json")
declare -a agent_names=("agent1" "agent2" "agent3")

# --- Create directories ---
echo "Creating necessary directories..."
mkdir -p vault-server/files
mkdir -p vault-agent1/config vault-agent2/config vault-agent3/config

# --- Create data files for Vault secrets ---
echo "Creating data files with random credentials..."
for i in "${!users[@]}"; do
  user_name=${users[$i]}
  random_url="https://$(generate_random_url)"
  random_password=$(generate_random_password)
  file_path="vault-server/files/${file_paths[$i]}"
  
  tee "$file_path" <<EOF
{
  "auth_method": "USERNAME_PASSWORD",
  "credentials": {
    "password": "${random_password}",
    "url": "${random_url}",
    "username": "${user_name}"
  }
}
EOF
done

# --- Create policy files ---
echo "Creating HCL policy files..."
for i in "${!customer_names[@]}"; do
  customer=${customer_names[$i]}
  agent=${agent_names[$i]}
  policy_file="vault-server/files/${agent}-policy.hcl"

  tee "$policy_file" <<EOF
path "secret/data/customers/${customer}" {
  capabilities = ["read", "list"]
}
EOF
done

# --- Put data into Vault ---
echo "Putting data into Vault..."
for i in "${!customer_names[@]}"; do
  vault kv put "secret/customers/${customer_names[$i]}" @"vault-server/files/${file_paths[$i]}"
done

# --- Verify data has been put ---
echo "Verifying data..."
for customer in "${customer_names[@]}"; do
  vault kv get "secret/customers/${customer}"
done

# --- Hardcoded Credentials ---
NEXUS_URL="http://${VM_IP}:18081"
NEXUS_USER="nadmin"
NEXUS_PASSWORD="nadmin123"

JENKINS_URL="http://${VM_IP}:8080"
JENKINS_USER="jadmin"
JENKINS_PASSWORD="jadmin123"

# --- Create data files in exact format ---
echo "Creating data files with exact JSON format..."

# Nexus credentials file
tee vault-server/files/nexus-data.json <<EOF
{
  "auth_method": "USERNAME_PASSWORD",
  "credentials": {
    "password": "${NEXUS_PASSWORD}",
    "url": "${NEXUS_URL}",
    "username": "${NEXUS_USER}"
  }
}
EOF

# Jenkins credentials file
tee vault-server/files/jenkins-data.json <<EOF
{
  "auth_method": "USERNAME_PASSWORD",
  "credentials": {
    "password": "${JENKINS_PASSWORD}",
    "url": "${JENKINS_URL}",
    "username": "${JENKINS_USER}"
  }
}
EOF

# --- Put data into Vault using exact format ---
echo "Putting data into Vault..."

# Store Nexus credentials
vault kv put secret/credentials/nexus @"vault-server/files/nexus-data.json"

# Store Jenkins credentials
vault kv put secret/credentials/jenkins @"vault-server/files/jenkins-data.json"

# --- Verify data has been put ---
echo "Verifying data..."

echo "=== Nexus Credentials ==="
vault kv get secret/credentials/nexus

echo "=== Jenkins Credentials ==="
vault kv get secret/credentials/jenkins

# --- Write policies to Vault ---
echo "Writing policies to Vault..."
vault policy write acme-agent1-policy vault-server/files/agent1-policy.hcl
vault policy write techcorp-agent2-policy vault-server/files/agent2-policy.hcl
vault policy write retailx-agent3-policy vault-server/files/agent3-policy.hcl

# --- Enable AppRole authentication method ---
echo "Enabling AppRole authentication method..."
vault auth enable approle

# --- Create AppRole roles with attached policies ---
echo "Creating AppRole roles..."
vault write auth/approle/role/agent1-acme token_ttl=3m token_max_ttl=9m policies="acme-agent1-policy"
vault write auth/approle/role/agent2-techcorp token_ttl=4m token_max_ttl=12m policies="techcorp-agent2-policy"
vault write auth/approle/role/agent3-retailx token_ttl=5m token_max_ttl=15m policies="retailx-agent3-policy"

# --- Verify AppRole roles ---
echo "Verifying AppRole roles..."
vault auth list
vault list /auth/approle/role

# --- Generate and store Role IDs and Secret IDs ---
echo "Generating and storing Role IDs and Secret IDs..."

# Agent1
vault read -format=json auth/approle/role/agent1-acme/role-id | jq -r '.data.role_id' > vault-agent1/config/role_id
vault write -f -format=json auth/approle/role/agent1-acme/secret-id | jq -r '.data.secret_id' > vault-agent1/config/secret_id

# Agent2
vault read -format=json auth/approle/role/agent2-techcorp/role-id | jq -r '.data.role_id' > vault-agent2/config/role_id
vault write -f -format=json auth/approle/role/agent2-techcorp/secret-id | jq -r '.data.secret_id' > vault-agent2/config/secret_id

# Agent3
vault read -format=json auth/approle/role/agent3-retailx/role-id | jq -r '.data.role_id' > vault-agent3/config/role_id
vault write -f -format=json auth/approle/role/agent3-retailx/secret-id | jq -r '.data.secret_id' > vault-agent3/config/secret_id

# --- Enable Userpass method and create one user ---
vault auth enable userpass
vault auth list
vault write auth/userpass/users/devops password=devops123 policies=acme-agent1-policy,retailx-agent3-policy,techcorp-agent2-policy

echo "Script complete. Role IDs and Secret IDs are saved in their respective directories."