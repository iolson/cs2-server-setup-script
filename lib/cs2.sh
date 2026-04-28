#!/usr/bin/env bash
# cs2.sh — CS2 dedicated server installation and validation

[[ -n "${_CS2_SH_LOADED:-}" ]] && return 0
_CS2_SH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/steamcmd.sh"

# ---------------------------------------------------------------------------
# install_cs2 — Full CS2 install: SteamCMD + game files + symlink fix
#
# Usage: install_cs2 "/opt/cs2"
# ---------------------------------------------------------------------------
install_cs2() {
    local install_dir="$1"

    install_steamcmd "${install_dir}"
    fix_steamclient_symlink "${install_dir}"
    update_cs2 "${install_dir}"
    validate_cs2_install "${install_dir}"
}

# ---------------------------------------------------------------------------
# validate_cs2_install — Verify the CS2 binary exists
#
# Usage: validate_cs2_install "/opt/cs2"
# ---------------------------------------------------------------------------
validate_cs2_install() {
    local install_dir="$1"
    local cs2_binary="${install_dir}/serverfiles/game/bin/linuxsteamrt64/cs2"

    if [[ ! -f "${cs2_binary}" ]]; then
        log_fatal "CS2 binary not found at ${cs2_binary} — installation may have failed"
    fi

    log_info "CS2 installation validated: ${cs2_binary}"
}
