#!/usr/bin/env bash
set -euo pipefail

# ======================
# Inputs
# ======================
NUM=3
while getopts "n:" opt; do
  case $opt in
    n) NUM="$OPTARG" ;;
  esac
done
shift $((OPTIND-1))

AWX_NS="awx"
AWX_NAME="awx"
VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"
AWX_PORT="${DEFAULT_HOST_PORT:-8081}"
AWX_URL="http://${VM_IP}:${AWX_PORT}"

KEY_FILE="${KEY_FILE:-./awx_client_key}"
START_PORT="${START_PORT:-2222}"

ORG_NAME="Demo Org"
INV_NAME="Client Lab"
SSH_CRED_NAME="Clients SSH Key"
VAULT_CRED_NAME="Vault (Dev)"
VAULT_INTERNAL_URL="http://vault.vault.svc:8200"   # AWX -> in-cluster Vault
VAULT_TOKEN="root"

# New Nexus credential configuration
NEXUS_CRED_TYPE_NAME="Get Password from HashiCorp Vault"
NEXUS_CRED_NAME="Nexus Cred"
NEXUS_VAULT_PATH="secret/data/credentials/nexus"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }; }
need kubectl; need curl; need jq

echo "[AWX] URL: ${AWX_URL}"

# ======================
# Admin Password
# ======================
echo "[AWX] Waiting for admin password secret..."
ADMIN_PASS=""
for i in {1..30}; do
  ADMIN_PASS="$(kubectl get secret ${AWX_NAME}-admin-password -n ${AWX_NS} \
    -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode || true)"
  [ -n "$ADMIN_PASS" ] && break
  sleep 2
done
[ -z "$ADMIN_PASS" ] && { echo "Failed to retrieve admin password"; exit 1; }

AUTH_BASIC="$(printf 'admin:%s' "${ADMIN_PASS}" | base64)"

# ======================
# Wait for AWX API
# ======================
echo "[AWX] Waiting for API..."
for i in {1..60}; do
  if curl -s "${AWX_URL}/api/v2/ping/" >/dev/null; then break; fi
  sleep 2
done
curl -s "${AWX_URL}/api/v2/ping/" >/dev/null || { echo "AWX API not reachable at ${AWX_URL}"; exit 1; }

# ======================
# Helpers
# ======================
get()  { curl -s -H "Authorization: Basic ${AUTH_BASIC}" "$@"; }
post() { curl -s -H "Authorization: Basic ${AUTH_BASIC}" -H "Content-Type: application/json" -d "$2" "$1"; }

encode_uri() { jq -rn --arg s "$1" '$s|@uri'; }

create_or_get_user() {
  local username=$1
  local password=$2
  local user_url="${AWX_URL}/api/v2/users/?username=$(encode_uri "${username}")"

  # Check if user already exists
  local user_id=$(get "${user_url}" | jq -r '.results[0].id // empty')

  if [ -z "${user_id}" ] || [ "${user_id}" = "null" ]; then
    echo "Creating new user: ${username}"
    local payload=$(jq -nc \
      --arg name "${username}" \
      --arg password "${password}" \
      '{"username": $name, "password": $password, "is_superuser": true, "is_active": true}')

    local response=$(post "${AWX_URL}/api/v2/users/" "${payload}")
    user_id=$(echo "${response}" | jq -r '.id')
  fi
  
  echo "${user_id}"
}

# ======================
# New User Creation
# ======================
NEW_USER_NAME="devops"
NEW_USER_PASS="devops123" # !! IMPORTANT: Change this password !!

echo "[AWX] Creating user: ${NEW_USER_NAME}"
NEW_USER_ID="$(create_or_get_user "${NEW_USER_NAME}" "${NEW_USER_PASS}")"
[ -z "${NEW_USER_ID}" ] && { echo "Failed to create or find user: ${NEW_USER_NAME}"; exit 1; }
echo "[AWX] User: ${NEW_USER_NAME} (id=${NEW_USER_ID})"

# ======================
# 1) Organization
# ======================
ENC_ORG_NAME="$(encode_uri "${ORG_NAME}")"
ORG_ID="$(get "${AWX_URL}/api/v2/organizations/?name=${ENC_ORG_NAME}" | jq -r '.results[0].id // empty')"
if [ -z "${ORG_ID}" ] || [ "${ORG_ID}" = "null" ]; then
  ORG_ID="$(post "${AWX_URL}/api/v2/organizations/" "{\"name\":\"${ORG_NAME}\"}" | jq -r '.id')"
fi
echo "[AWX] Org: ${ORG_NAME} (id=${ORG_ID})"

# ======================
# 2) Inventory
# ======================
ENC_INV_NAME="$(encode_uri "${INV_NAME}")"
INV_ID="$(get "${AWX_URL}/api/v2/inventories/?name=${ENC_INV_NAME}&organization=${ORG_ID}" | jq -r '.results[0].id // empty')"
if [ -z "${INV_ID}" ] || [ "${INV_ID}" = "null" ]; then
  INV_ID="$(post "${AWX_URL}/api/v2/inventories/" "{\"name\":\"${INV_NAME}\",\"organization\":${ORG_ID}}" | jq -r '.id')"
fi
echo "[AWX] Inventory: ${INV_NAME} (id=${INV_ID})"

# ======================
# 3) SSH Credential
# ======================
PRIV_KEY="$(cat "${KEY_FILE}")"
ENC_SSH_CRED_NAME="$(encode_uri "${SSH_CRED_NAME}")"
CRED_ID="$(get "${AWX_URL}/api/v2/credentials/?name=${ENC_SSH_CRED_NAME}&organization=${ORG_ID}" | jq -r '.results[0].id // empty')"
if [ -z "${CRED_ID}" ] || [ "${CRED_ID}" = "null" ]; then
  MACH_TYPE_ID="$(get "${AWX_URL}/api/v2/credential_types/?kind=ssh" | jq -r '.results[0].id')"
  CRED_ID="$(post "${AWX_URL}/api/v2/credentials/" \
    "$(jq -nc \
      --arg name "${SSH_CRED_NAME}" \
      --arg pk "${PRIV_KEY}" \
      --arg user "ansible" \
      --argjson org "${ORG_ID}" \
      --argjson type_id "${MACH_TYPE_ID}" \
      '{name:$name, organization:$org, credential_type:$type_id, inputs:{username:$user, ssh_key_data:$pk}}')" \
    | jq -r '.id')"
fi
echo "[AWX] SSH Credential: ${SSH_CRED_NAME} (id=${CRED_ID})"

# ======================
# 4) Vault Credential
# ======================
ENC_VAULT_CRED_NAME="$(encode_uri "${VAULT_CRED_NAME}")"
VAULT_CRED_ID="$(get "${AWX_URL}/api/v2/credentials/?name=${ENC_VAULT_CRED_NAME}&organization=${ORG_ID}" | jq -r '.results[0].id // empty')"
if [ -z "${VAULT_CRED_ID}" ] || [ "${VAULT_CRED_ID}" = "null" ]; then
  VAULT_TYPE_ID="$(get "${AWX_URL}/api/v2/credential_types/?name=HashiCorp%20Vault%20Secret%20Lookup" | jq -r '.results[0].id')"
  VAULT_CRED_ID="$(post "${AWX_URL}/api/v2/credentials/" \
    "$(jq -nc \
      --arg name "${VAULT_CRED_NAME}" \
      --arg url "${VAULT_INTERNAL_URL}" \
      --arg token "${VAULT_TOKEN}" \
      --argjson org "${ORG_ID}" \
      --argjson type_id "${VAULT_TYPE_ID}" \
      '{name:$name, organization:$org, credential_type:$type_id, inputs:{url:$url, token:$token}}')" \
    | jq -r '.id')"
fi
echo "[AWX] Vault Credential: ${VAULT_CRED_NAME} (id=${VAULT_CRED_ID})"

# ======================
# 4.5) Custom Credential Type - Vault Password Lookup
# ======================
ENC_NEXUS_CRED_TYPE="$(encode_uri "${NEXUS_CRED_TYPE_NAME}")"
NEXUS_CRED_TYPE_ID="$(get "${AWX_URL}/api/v2/credential_types/?name=${ENC_NEXUS_CRED_TYPE}" | jq -r '.results[0].id // empty')"

if [ -z "${NEXUS_CRED_TYPE_ID}" ] || [ "${NEXUS_CRED_TYPE_ID}" = "null" ]; then
  echo "[AWX] Creating custom credential type: ${NEXUS_CRED_TYPE_NAME}"
  
  NEXUS_CRED_TYPE_PAYLOAD="$(jq -nc \
    --arg name "${NEXUS_CRED_TYPE_NAME}" \
    --arg desc "Read Vault KV Secret Engine" \
    '{
      name: $name,
      description: $desc,
      kind: "cloud",
      inputs: {
        fields: [
          {
            id: "data",
            type: "string",
            label: "Password data from Vault"
          }
        ]
      },
      injectors: {
        extra_vars: {
          Vault_data_raw: "{{ data }}"
        }
      }
    }')"

  CREATE_RESPONSE="$(post "${AWX_URL}/api/v2/credential_types/" "${NEXUS_CRED_TYPE_PAYLOAD}")"
  NEXUS_CRED_TYPE_ID="$(echo "${CREATE_RESPONSE}" | jq -r '.id // empty')"
  
  if [ -z "${NEXUS_CRED_TYPE_ID}" ] || [ "${NEXUS_CRED_TYPE_ID}" = "null" ]; then
    echo "[ERROR] Failed to create credential type. Response:"
    echo "${CREATE_RESPONSE}" | jq .
    exit 1
  fi
fi

echo "[AWX] Custom Credential Type: ${NEXUS_CRED_TYPE_NAME} (id=${NEXUS_CRED_TYPE_ID})"

# ======================
# 4.6) Nexus Credential using Custom Type
# ======================
ENC_NEXUS_CRED_NAME="$(encode_uri "${NEXUS_CRED_NAME}")"
NEXUS_CRED_ID="$(get "${AWX_URL}/api/v2/credentials/?name=${ENC_NEXUS_CRED_NAME}" | jq -r '.results[0].id // empty')"

if [ -z "${NEXUS_CRED_ID}" ] || [ "${NEXUS_CRED_ID}" = "null" ]; then
  echo "[AWX] Creating Nexus credential: ${NEXUS_CRED_NAME}"
  
  NEXUS_CRED_PAYLOAD="$(jq -nc \
    --arg name "${NEXUS_CRED_NAME}" \
    --arg desc "Nexus Credential read from Vault" \
    --argjson type_id "${NEXUS_CRED_TYPE_ID}" \
    --argjson org "${ORG_ID}" \
    '{
      name: $name,
      description: $desc,
      credential_type: $type_id,
      organization: $org|tonumber,
      inputs: {}
    }')"

  CREATE_RESPONSE="$(post "${AWX_URL}/api/v2/credentials/" "${NEXUS_CRED_PAYLOAD}")"
  NEXUS_CRED_ID="$(echo "${CREATE_RESPONSE}" | jq -r '.id // empty')"
  
  if [ -z "${NEXUS_CRED_ID}" ] || [ "${NEXUS_CRED_ID}" = "null" ]; then
    echo "[ERROR] Failed to create credential. Response:"
    echo "${CREATE_RESPONSE}" | jq .
    exit 1
  fi
  
  # Create input source linking to Vault
  echo "[AWX] Creating input source for Nexus credential..."
  
  INPUT_SOURCE_PAYLOAD="$(jq -nc \
    --argjson vault_cred "${VAULT_CRED_ID}" \
    --arg secret_path "${NEXUS_VAULT_PATH}" \
    '{
      input_field_name: "data",
      source_credential: $vault_cred,
      metadata: {
        secret_path: $secret_path,
        secret_key: "data"
      }
    }')"
  
  INPUT_SOURCE_RESPONSE="$(post "${AWX_URL}/api/v2/credentials/${NEXUS_CRED_ID}/input_sources/" "${INPUT_SOURCE_PAYLOAD}")"
  INPUT_SOURCE_ID="$(echo "${INPUT_SOURCE_RESPONSE}" | jq -r '.id // empty')"
  
  if [ -z "${INPUT_SOURCE_ID}" ] || [ "${INPUT_SOURCE_ID}" = "null" ]; then
    echo "[ERROR] Failed to create input source. Response:"
    echo "${INPUT_SOURCE_RESPONSE}" | jq .
    exit 1
  fi
  echo "[AWX] Input source created (id=${INPUT_SOURCE_ID})"
fi

echo "[AWX] Nexus Credential: ${NEXUS_CRED_NAME} (id=${NEXUS_CRED_ID})"

# ======================
# 5) Hosts
# ======================
for i in $(seq 1 "${NUM}"); do
  hname="client-${i}"
  port=$((START_PORT + i - 1))

  # --- LOGIC: Define Host-Specific Type and App ---
  # Default values
  CUSTOM_TYPE="client"
  CUSTOM_APP="web"

  case $i in
    1) # Corresponds to client-1 (e.g., controlplane)
      CUSTOM_TYPE="controlplane"
      CUSTOM_APP="web"
      CUSTOM_ENV="prod"
      ;;
    2) # Corresponds to client-2 (e.g., node01)
      CUSTOM_TYPE="server"
      CUSTOM_APP="db"
      CUSTOM_ENV="prod"
      ;;
    *) # Default for client-3 and subsequent hosts
      CUSTOM_TYPE="client"
      CUSTOM_APP="general"
      CUSTOM_ENV="dev"
      ;;
  esac

  # Build variables block as proper YAML string
  VARS=$(printf "ansible_host: %s\nansible_port: %s\nansible_user: ansible\ntype: %s\napp: %s\nenv: %s" \
    "${VM_IP}" "${port}" "${CUSTOM_TYPE}" "${CUSTOM_APP}" "${CUSTOM_ENV}")

  # Check if host already exists
  HID="$(get "${AWX_URL}/api/v2/hosts/?name=${hname}&inventory=${INV_ID}" | jq -r '.results[0].id // empty')"

  if [ -z "${HID}" ] || [ "${HID}" = "null" ]; then
    PAYLOAD="$(jq -nc \
      --arg name "${hname}" \
      --argjson inv "${INV_ID}" \
      --arg vars "${VARS}" \
      '{name:$name, inventory:$inv, variables:$vars}')"

    echo "[DEBUG] Creating host with payload:"
    echo "${PAYLOAD}" | jq .

    HID="$(post "${AWX_URL}/api/v2/hosts/" "${PAYLOAD}" | jq -r '.id')"
  fi

  echo "[AWX] Host: ${hname} (id=${HID}) [type=${CUSTOM_TYPE}, app=${CUSTOM_APP}, env=${CUSTOM_ENV}]"
done

# ======================
# 6) Project
# ======================
PROJECT_NAME="KNS Project"
GITHUB_REPO="https://github.com/Knsan1/ansible-awx-repo.git"
PROJECT_SCMM_TYPE="git"   # git, svn, etc.

# Check if project exists
ENC_PROJECT_NAME=$(jq -rn --arg s "$PROJECT_NAME" '$s|@uri')
PROJECT_ID="$(get "${AWX_URL}/api/v2/projects/?name=${ENC_PROJECT_NAME}" | jq -r '.results[0].id // empty')"

if [ -z "${PROJECT_ID}" ] || [ "${PROJECT_ID}" = "null" ]; then
  PAYLOAD="$(jq -nc \
    --arg name "${PROJECT_NAME}" \
    --arg org_id "${ORG_ID}" \
    --arg scm_type "${PROJECT_SCMM_TYPE}" \
    --arg scm_url "${GITHUB_REPO}" \
    '{name:$name, organization:$org_id|tonumber, scm_type:$scm_type, scm_url:$scm_url}')"

  echo "[DEBUG] Creating project with payload:"
  echo "${PAYLOAD}" | jq .

  PROJECT_ID="$(post "${AWX_URL}/api/v2/projects/" "${PAYLOAD}" | jq -r '.id')"
fi

echo "[AWX] Project: ${PROJECT_NAME} (id=${PROJECT_ID})"

# ======================
# Done
# ======================
echo "========================================================"
echo "✅ AWX Setup Complete!"
echo ""
echo "Organization: ${ORG_NAME} (id=${ORG_ID})"
echo "Inventory: ${INV_NAME} (id=${INV_ID})"
echo "SSH Credential: ${SSH_CRED_NAME} (id=${CRED_ID})"
echo "Vault Credential: ${VAULT_CRED_NAME} (id=${VAULT_CRED_ID})"
echo "Custom Credential Type: ${NEXUS_CRED_TYPE_NAME} (id=${NEXUS_CRED_TYPE_ID})"
echo "Nexus Credential: ${NEXUS_CRED_NAME} (id=${NEXUS_CRED_ID})"
echo "  - Vault Path: ${NEXUS_VAULT_PATH}"
echo "  - Injected Variable: Vault_data_raw"
echo "Hosts added: ${NUM}"
for i in $(seq 1 "${NUM}"); do
  echo "  - client-${i} (port $((START_PORT + i - 1)))"
done
echo "Project: ${PROJECT_NAME} (id=${PROJECT_ID})"
echo "  - GitHub repo: ${GITHUB_REPO}"
echo ""
echo "You can now create Templates in AWX using:"
echo "  - Inventory: '${INV_NAME}'"
echo "  - SSH Credential: '${SSH_CRED_NAME}'"
echo "  - Nexus Credential: '${NEXUS_CRED_NAME}' (reads from Vault)"
echo "  - Project: '${PROJECT_NAME}'"
echo ""
echo "Try a simple ad-hoc ping from AWX using the '${SSH_CRED_NAME}' credential to verify hosts."
echo "========================================================"