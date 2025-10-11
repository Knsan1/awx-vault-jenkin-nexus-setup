#!/usr/bin/env bash
set -uo pipefail

# ======================
# Inputs
# ======================
AWX_NS="awx"
AWX_NAME="awx"
VM_IP="$(./detect_vm_ip.sh || echo 127.0.0.1)"
AWX_PORT="${DEFAULT_HOST_PORT:-8081}"
AWX_URL="http://${VM_IP}:${AWX_PORT}"

ORG_NAME="Demo Org"
INV_NAME="Client Lab"
PROJECT_NAME="KNS Project"

# Define Job Templates: name|playbook_path
declare -A JOB_TEMPLATES=(
  ["NFS System Setup"]="01_nfs_system.yaml"
  ["Data Gather"]="02_data_gather.yaml"
  ["Package Install"]="03_package_update_or_install.yaml"
  ["Package Update"]="03_package_update_or_install.yaml"
  ["Enterprise Patching"]="04_enterprise_patching.yaml"
  ["Nexus File Copying"]="05_nexus_copy_file.yaml"
  ["Collect Info"]="ad-hoc/collect_info.yml"
  ["Display Info"]="ad-hoc/display_info.yml"
  ["Ping Hosts"]="ad-hoc/ping.yml"
)

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

# ======================
# 1) Get Organization
# ======================
ENC_ORG_NAME="$(encode_uri "${ORG_NAME}")"
ORG_ID="$(get "${AWX_URL}/api/v2/organizations/?name=${ENC_ORG_NAME}" | jq -r '.results[0].id // empty')"
[ -z "${ORG_ID}" ] && { echo "Organization '${ORG_NAME}' not found"; exit 1; }
echo "[AWX] Organization: ${ORG_NAME} (id=${ORG_ID})"

# ======================
# 2) Get Inventory
# ======================
ENC_INV_NAME="$(encode_uri "${INV_NAME}")"
INV_ID="$(get "${AWX_URL}/api/v2/inventories/?name=${ENC_INV_NAME}&organization=${ORG_ID}" | jq -r '.results[0].id // empty')"
[ -z "${INV_ID}" ] && { echo "Inventory '${INV_NAME}' not found"; exit 1; }
echo "[AWX] Inventory: ${INV_NAME} (id=${INV_ID})"

# ======================
# 5) Get Project
# ======================
ENC_PROJECT_NAME="$(encode_uri "${PROJECT_NAME}")"
PROJECT_ID="$(get "${AWX_URL}/api/v2/projects/?name=${ENC_PROJECT_NAME}" | jq -r '.results[0].id // empty')"
[ -z "${PROJECT_ID}" ] && { echo "Project '${PROJECT_NAME}' not found"; exit 1; }
echo "[AWX] Project: ${PROJECT_NAME} (id=${PROJECT_ID})"

# ======================
# 6) Create Job Templates
# ======================
echo "[DEBUG] Total Job Templates to process: ${#JOB_TEMPLATES[@]}"
CREATED_COUNT=0
for TEMPLATE_NAME in "${!JOB_TEMPLATES[@]}"; do
  PLAYBOOK_PATH="${JOB_TEMPLATES[$TEMPLATE_NAME]}"
  echo "[AWX] Processing Job Template: ${TEMPLATE_NAME} (playbook: ${PLAYBOOK_PATH})"

  ENC_TEMPLATE_NAME="$(encode_uri "${TEMPLATE_NAME}")"
  JOB_TEMPLATE_ID="$(get "${AWX_URL}/api/v2/job_templates/?name=${ENC_TEMPLATE_NAME}&project=${PROJECT_ID}" | jq -r '.results[0].id // empty')"
  if [ -z "${JOB_TEMPLATE_ID}" ] || [ "${JOB_TEMPLATE_ID}" = "null" ]; then
    # Build minimal payload
    PAYLOAD=$(jq -nc \
      --arg name "${TEMPLATE_NAME}" \
      --argjson project "${PROJECT_ID}" \
      --argjson inventory "${INV_ID}" \
      --arg playbook "${PLAYBOOK_PATH}" \
      '{name:$name, project:$project, inventory:$inventory, playbook:$playbook}')

    echo "[DEBUG] Creating Job Template with payload:"
    echo "${PAYLOAD}" | jq .

    RESPONSE=$(post "${AWX_URL}/api/v2/job_templates/" "${PAYLOAD}")
    JOB_TEMPLATE_ID=$(echo "${RESPONSE}" | jq -r '.id')
    if [ -z "${JOB_TEMPLATE_ID}" ] || [ "${JOB_TEMPLATE_ID}" = "null" ]; then
      echo "[ERROR] Failed to create Job Template '${TEMPLATE_NAME}': $(echo "${RESPONSE}" | jq -r '.')"
    else
      ((CREATED_COUNT++))
      echo "[AWX] Job Template: ${TEMPLATE_NAME} (id=${JOB_TEMPLATE_ID})"
    fi
  else
    echo "[INFO] Job Template '${TEMPLATE_NAME}' already exists (id=${JOB_TEMPLATE_ID}), skipping creation"
  fi
done

# ======================
# Done
# ======================
echo "========================================================"
echo "✅ Job Templates Setup Complete! Created ${CREATED_COUNT} out of ${#JOB_TEMPLATES[@]} templates."
echo ""
for TEMPLATE_NAME in "${!JOB_TEMPLATES[@]}"; do
  PLAYBOOK_PATH="${JOB_TEMPLATES[$TEMPLATE_NAME]}"
  JOB_TEMPLATE_ID="$(get "${AWX_URL}/api/v2/job_templates/?name=$(encode_uri "${TEMPLATE_NAME}")&project=${PROJECT_ID}" | jq -r '.results[0].id // empty')"
  echo "Job Template: ${TEMPLATE_NAME} (id=${JOB_TEMPLATE_ID})"
  echo "  - Project: ${PROJECT_NAME} (id=${PROJECT_ID})"
  echo "  - Playbook: ${PLAYBOOK_PATH}"
  echo "  - Inventory: ${INV_NAME} (id=${INV_ID})"
done
echo ""
echo "You can now run the Job Templates in AWX to execute the specified playbooks."
echo "Verify the setup by launching the Job Templates from the AWX UI or API."
echo "For NFS setup, ensure 'awx-client-2:/share' is exported correctly before running 'NFS System Setup'."
echo "========================================================"