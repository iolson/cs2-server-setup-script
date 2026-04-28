#!/usr/bin/env bash
# remove-instance.sh — Remove (archive) a CS2 server instance
# Usage: sudo ./remove-instance.sh N
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
source "${LIB_DIR}/firewall.sh"
source "${LIB_DIR}/instance.sh"

# Check root
if [[ $EUID -ne 0 ]]; then
    log_fatal "This script must be run as root"
fi

# Validate arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <instance_number>"
    echo "Example: $0 3"
    exit 1
fi

INSTANCE_NUM="$1"
INSTANCE_DIR="${INSTALL_DIR}/instances/server-${INSTANCE_NUM}"
SERVICE_NAME="cs2-server-${INSTANCE_NUM}.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"

if [[ ! -d "$INSTANCE_DIR" ]]; then
    log_fatal "Instance directory not found: ${INSTANCE_DIR}"
fi

log_step "Removing instance: server-${INSTANCE_NUM}"

if ! prompt_yes_no "Are you sure you want to remove server-${INSTANCE_NUM}?" "no"; then
    log_info "Cancelled"
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Stop and disable service
# ---------------------------------------------------------------------------
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    log_info "Stopping ${SERVICE_NAME}..."
    systemctl stop "$SERVICE_NAME"
fi

if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl disable "$SERVICE_NAME"
fi

# ---------------------------------------------------------------------------
# 2. Remove firewall rules
# ---------------------------------------------------------------------------
GAME_PORT=$(calc_game_port "$INSTANCE_NUM")
GOTV_PORT=$(calc_gotv_port "$INSTANCE_NUM")
remove_ufw_for_instance "$GAME_PORT" "$GOTV_PORT"

# ---------------------------------------------------------------------------
# 3. Archive instance directory
# ---------------------------------------------------------------------------
ARCHIVE_DIR="${INSTALL_DIR}/instances/.archive"
mkdir -p "$ARCHIVE_DIR"
ARCHIVE_NAME="server-${INSTANCE_NUM}.$(date +%Y%m%d_%H%M%S)"
mv "$INSTANCE_DIR" "${ARCHIVE_DIR}/${ARCHIVE_NAME}"
log_info "Instance archived to: ${ARCHIVE_DIR}/${ARCHIVE_NAME}"

# ---------------------------------------------------------------------------
# 4. Remove log directory symlink and systemd unit
# ---------------------------------------------------------------------------
CSGO_CFG_LINK="${INSTALL_DIR}/serverfiles/game/csgo/cfg/server-${INSTANCE_NUM}"
if [[ -L "$CSGO_CFG_LINK" ]]; then
    rm "$CSGO_CFG_LINK"
fi

if [[ -f "$SERVICE_FILE" ]]; then
    rm "$SERVICE_FILE"
    systemctl daemon-reload
fi

log_info "Instance server-${INSTANCE_NUM} removed successfully"
log_info "Archived config available at: ${ARCHIVE_DIR}/${ARCHIVE_NAME}"
