#!/usr/bin/env bash
# firewall.sh — UFW firewall rule management for CS2 instances

[[ -n "${_FIREWALL_SH_LOADED:-}" ]] && return 0
_FIREWALL_SH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---------------------------------------------------------------------------
# is_ufw_active — Check if UFW is active
# Returns 0 if active, 1 if not
# ---------------------------------------------------------------------------
is_ufw_active() {
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# configure_ufw_for_instance — Open firewall ports for a CS2 instance
#
# Usage: configure_ufw_for_instance 27015 27020
#        (game_port, gotv_port)
# ---------------------------------------------------------------------------
configure_ufw_for_instance() {
    local game_port="$1"
    local gotv_port="$2"

    if ! is_ufw_active; then
        log_info "UFW is not active, skipping firewall configuration"
        return 0
    fi

    log_info "Opening firewall ports: game=${game_port} (TCP+UDP), GOTV=${gotv_port} (UDP)"

    ufw allow "${game_port}/tcp" comment "CS2 game port" >/dev/null
    ufw allow "${game_port}/udp" comment "CS2 game port" >/dev/null
    ufw allow "${gotv_port}/udp" comment "CS2 GOTV port" >/dev/null
}

# ---------------------------------------------------------------------------
# remove_ufw_for_instance — Remove firewall rules for a CS2 instance
#
# Usage: remove_ufw_for_instance 27015 27020
# ---------------------------------------------------------------------------
remove_ufw_for_instance() {
    local game_port="$1"
    local gotv_port="$2"

    if ! is_ufw_active; then
        return 0
    fi

    log_info "Removing firewall rules for ports: game=${game_port}, GOTV=${gotv_port}"

    ufw delete allow "${game_port}/tcp" >/dev/null 2>&1 || true
    ufw delete allow "${game_port}/udp" >/dev/null 2>&1 || true
    ufw delete allow "${gotv_port}/udp" >/dev/null 2>&1 || true
}
