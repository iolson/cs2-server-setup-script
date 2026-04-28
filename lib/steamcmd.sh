#!/usr/bin/env bash
# steamcmd.sh — SteamCMD installation and CS2 update functions

[[ -n "${_STEAMCMD_SH_LOADED:-}" ]] && return 0
_STEAMCMD_SH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---------------------------------------------------------------------------
# install_steamcmd — Download, extract, and self-update SteamCMD
#
# Usage: install_steamcmd "/opt/cs2"
# Idempotent: skips download if steamcmd.sh already exists
# ---------------------------------------------------------------------------
install_steamcmd() {
    local install_dir="$1"
    local steamcmd_dir="${install_dir}/steamcmd"

    if [[ -x "${steamcmd_dir}/steamcmd.sh" ]]; then
        log_info "SteamCMD already installed at ${steamcmd_dir}"
    else
        log_step "Installing SteamCMD"
        mkdir -p "${steamcmd_dir}"
        curl -fsSL "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" \
            | tar -xz -C "${steamcmd_dir}"
    fi

    log_step "Running SteamCMD self-update"
    "${steamcmd_dir}/steamcmd.sh" +quit || true
}

# ---------------------------------------------------------------------------
# fix_steamclient_symlink — Suppress runtime warning about steamclient.so
#
# Usage: fix_steamclient_symlink "/opt/cs2"
# ---------------------------------------------------------------------------
fix_steamclient_symlink() {
    local install_dir="$1"
    local steamcmd_dir="${install_dir}/steamcmd"
    local target_dir="${HOME:?HOME must be set for steamclient symlink}/.steam/sdk64"

    mkdir -p "${target_dir}"
    if [[ -f "${steamcmd_dir}/linux64/steamclient.so" ]]; then
        ln -sfn "${steamcmd_dir}/linux64/steamclient.so" "${target_dir}/steamclient.so"
        log_info "Created steamclient.so symlink"
    fi
}

# ---------------------------------------------------------------------------
# update_cs2 — Install or update CS2 dedicated server via SteamCMD
#
# Usage: update_cs2 "/opt/cs2"
# ---------------------------------------------------------------------------
update_cs2() {
    local install_dir="$1"
    local steamcmd_dir="${install_dir}/steamcmd"
    local serverfiles_dir="${install_dir}/serverfiles"

    mkdir -p "${serverfiles_dir}"

    log_step "Installing/updating CS2 dedicated server (App 730)"
    "${steamcmd_dir}/steamcmd.sh" \
        +force_install_dir "${serverfiles_dir}" \
        +login anonymous \
        +app_update 730 validate \
        +quit
}
