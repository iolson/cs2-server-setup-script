#!/usr/bin/env bash
# update-servers.sh — Stop servers, update CS2 via SteamCMD, restart
# This script is installed to %%INSTALL_DIR%%/scripts/ by setup.sh

set -euo pipefail

INSTALL_DIR="%%INSTALL_DIR%%"
SERVICE_USER="%%SERVICE_USER%%"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "${SCRIPT_DIR}")"

# Source from installed location or repo
if [[ -f "${LIB_DIR}/lib/common.sh" ]]; then
    source "${LIB_DIR}/lib/common.sh"
elif [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    source "${SCRIPT_DIR}/../lib/common.sh"
fi

# Check root
if [[ $EUID -ne 0 ]]; then
    log_fatal "This script must be run as root"
fi

log_step "CS2 Server Update"

# ---------------------------------------------------------------------------
# 1. Record which services are currently running
# ---------------------------------------------------------------------------
RUNNING_SERVICES=()
for unit in /etc/systemd/system/cs2-server-*.service; do
    [[ -f "$unit" ]] || continue
    svc=$(basename "$unit")
    if systemctl is-active --quiet "$svc"; then
        RUNNING_SERVICES+=("$svc")
    fi
done

if [[ ${#RUNNING_SERVICES[@]} -gt 0 ]]; then
    log_info "Stopping ${#RUNNING_SERVICES[@]} running server(s)..."
    for svc in "${RUNNING_SERVICES[@]}"; do
        systemctl stop "$svc"
        log_info "  Stopped ${svc}"
    done
else
    log_info "No running CS2 servers found"
fi

# ---------------------------------------------------------------------------
# 2. Update CS2 via SteamCMD
# ---------------------------------------------------------------------------
log_step "Updating CS2 via SteamCMD"
"${INSTALL_DIR}/steamcmd/steamcmd.sh" \
    +force_install_dir "${INSTALL_DIR}/serverfiles" \
    +login anonymous \
    +app_update 730 validate \
    +quit

# ---------------------------------------------------------------------------
# 3. Re-patch gameinfo.gi if Metamod is installed
# ---------------------------------------------------------------------------
GAMEINFO="${INSTALL_DIR}/serverfiles/game/csgo/gameinfo.gi"
if [[ -d "${INSTALL_DIR}/serverfiles/game/csgo/addons/metamod" ]]; then
    if [[ -f "$GAMEINFO" ]] && ! grep -q "csgo/addons/metamod" "$GAMEINFO"; then
        log_step "Re-patching gameinfo.gi for Metamod"
        sed -i "/Game_LowViolence/a\\\\t\\t\\tGame\\tcsgo/addons/metamod" "$GAMEINFO"
        log_info "gameinfo.gi re-patched"
    else
        log_info "gameinfo.gi already patched for Metamod"
    fi
fi

# ---------------------------------------------------------------------------
# 4. Recreate instance symlinks (may be wiped by SteamCMD validate)
# ---------------------------------------------------------------------------
log_step "Recreating instance symlinks"
CSGO_CFG_DIR="${INSTALL_DIR}/serverfiles/game/csgo/cfg"
for dir in "${INSTALL_DIR}/instances"/server-*/; do
    [[ -d "$dir" ]] || continue
    instance_num=$(basename "$dir" | sed 's/server-//')
    if [[ -d "${dir}cfg" ]]; then
        ln -sfn "${dir}cfg" "${CSGO_CFG_DIR}/server-${instance_num}"
        log_info "  Linked server-${instance_num}"
    fi
done

# ---------------------------------------------------------------------------
# 5. Fix permissions
# ---------------------------------------------------------------------------
chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"

# ---------------------------------------------------------------------------
# 6. Restart previously-running services
# ---------------------------------------------------------------------------
if [[ ${#RUNNING_SERVICES[@]} -gt 0 ]]; then
    log_step "Restarting ${#RUNNING_SERVICES[@]} server(s)..."
    for svc in "${RUNNING_SERVICES[@]}"; do
        systemctl start "$svc"
        log_info "  Started ${svc}"
        sleep 5
    done
fi

log_info "Update complete"
