#!/usr/bin/env bash
# add-instance.sh — Add a new CS2 server instance
# This script is installed to %%INSTALL_DIR%%/scripts/ by setup.sh

set -euo pipefail

INSTALL_DIR="%%INSTALL_DIR%%"
SERVICE_USER="%%SERVICE_USER%%"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    LIB_DIR="${SCRIPT_DIR}/../lib"
else
    LIB_DIR="$(dirname "${SCRIPT_DIR}")/lib"
fi

source "${LIB_DIR}/common.sh"
source "${LIB_DIR}/validation.sh"
source "${LIB_DIR}/instance.sh"

# Locate templates
if [[ -d "${SCRIPT_DIR}/../templates" ]]; then
    TEMPLATE_DIR="${SCRIPT_DIR}/../templates"
else
    TEMPLATE_DIR="$(dirname "${SCRIPT_DIR}")/templates"
fi

# Check root
if [[ $EUID -ne 0 ]]; then
    log_fatal "This script must be run as root"
fi

# ---------------------------------------------------------------------------
# Detect next instance number
# ---------------------------------------------------------------------------
NEXT_NUM=1
for dir in "${INSTALL_DIR}/instances"/server-*/; do
    [[ -d "$dir" ]] || continue
    num=$(basename "$dir" | sed 's/server-//')
    if (( num >= NEXT_NUM )); then
        NEXT_NUM=$(( num + 1 ))
    fi
done

log_step "Adding new instance: server-${NEXT_NUM}"
echo ""

# ---------------------------------------------------------------------------
# Collect configuration
# ---------------------------------------------------------------------------
# Public IP from first existing instance
PUBLIC_IP=""
for envfile in "${INSTALL_DIR}/instances"/server-*/instance.env; do
    [[ -f "$envfile" ]] || continue
    PUBLIC_IP=$(grep "^CS2_PUBLIC_IP=" "$envfile" | head -n1 | cut -d= -f2)
    break
done
if [[ -z "$PUBLIC_IP" ]]; then
    PUBLIC_IP=$(curl -fsSL --connect-timeout 5 ifconfig.me 2>/dev/null || echo "")
fi
while [[ -z "$PUBLIC_IP" ]] || ! validate_ip_address "$PUBLIC_IP"; do
    PUBLIC_IP=$(prompt_value "Server public IP" "")
done

# eBot config from first existing instance
EBOT_IP=""
EBOT_PORT=""
for envfile in "${INSTALL_DIR}/instances"/server-*/instance.env; do
    [[ -f "$envfile" ]] || continue
    EBOT_IP=$(grep "^CS2_EBOT_IP=" "$envfile" | head -n1 | cut -d= -f2)
    EBOT_PORT=$(grep "^CS2_EBOT_PORT=" "$envfile" | head -n1 | cut -d= -f2)
    EBOT_LOG_ADDRESS=$(grep "^CS2_EBOT_LOG_ADDRESS=" "$envfile" | head -n1 | cut -d= -f2-)
    break
done

if [[ -z "$EBOT_IP" ]]; then
    while true; do
        EBOT_IP=$(prompt_value "eBot logs-receiver IP" "")
        [[ -n "$EBOT_IP" ]] && validate_ip_address "$EBOT_IP" && break
    done
fi
EBOT_PORT="${EBOT_PORT:-12345}"
EBOT_LOG_ADDRESS="${EBOT_LOG_ADDRESS:-http://${EBOT_IP}:${EBOT_PORT}}"

# Instance-specific prompts
HOSTNAME=$(prompt_value "Server hostname" "CS2 Server ${NEXT_NUM}")

GSLT=""
while true; do
    GSLT=$(prompt_value "GSLT token (App 730)" "")
    [[ -n "$GSLT" ]] && validate_gslt_token "$GSLT" && break
done

DEFAULT_RCON=$(generate_password 24)
RCON_PASS=$(prompt_value "RCON password" "${DEFAULT_RCON}")
SERVER_PASS=$(prompt_value "Server password (empty = public)" "")

if prompt_yes_no "Enable GOTV?" "yes"; then
    GOTV="1"
else
    GOTV="0"
fi

MAX_PLAYERS=$(prompt_value "Max players" "12")

echo ""
GAME_PORT=$(calc_game_port "$NEXT_NUM")
GOTV_PORT=$(calc_gotv_port "$NEXT_NUM")
log_info "Instance: server-${NEXT_NUM}, Game Port: ${GAME_PORT}, GOTV Port: ${GOTV_PORT}"

if ! prompt_yes_no "Proceed?" "yes"; then
    log_info "Cancelled"
    exit 0
fi

# ---------------------------------------------------------------------------
# Create instance
# ---------------------------------------------------------------------------
setup_instance \
    "${INSTALL_DIR}" \
    "${NEXT_NUM}" \
    "${TEMPLATE_DIR}" \
    "${HOSTNAME}" \
    "${GSLT}" \
    "${RCON_PASS}" \
    "${SERVER_PASS}" \
    "${GOTV}" \
    "${MAX_PLAYERS}" \
    "${PUBLIC_IP}" \
    "${EBOT_IP}" \
    "${EBOT_PORT}" \
    "${SERVICE_USER}" \
    "${EBOT_LOG_ADDRESS}"

write_credentials_file "${INSTALL_DIR}" "${NEXT_NUM}" "${RCON_PASS}" "${GAME_PORT}"

# Fix permissions
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}/instances/server-${NEXT_NUM}"
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}/logs/server-${NEXT_NUM}"
chmod 750 "${INSTALL_DIR}/instances/server-${NEXT_NUM}"
find "${INSTALL_DIR}/instances/server-${NEXT_NUM}" -type f -exec chmod 640 {} \;

# Enable service
systemctl daemon-reload
systemctl enable "cs2-server-${NEXT_NUM}.service"

if prompt_yes_no "Start server-${NEXT_NUM} now?" "yes"; then
    systemctl start "cs2-server-${NEXT_NUM}.service"
    log_info "server-${NEXT_NUM} started"
fi

log_info "Instance server-${NEXT_NUM} added successfully"
