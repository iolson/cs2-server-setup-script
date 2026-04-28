#!/usr/bin/env bash
# setup.sh — Interactive CS2 dedicated server setup script
# Provisions N CS2 server instances on Ubuntu 24.04 LTS bare metal
# Designed for LAN tournaments using eBot for match management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates"

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/cs2.sh"
source "${SCRIPT_DIR}/lib/metamod.sh"
source "${SCRIPT_DIR}/lib/instance.sh"

# ============================================================================
# Preflight checks
# ============================================================================
preflight_checks() {
    log_step "Running preflight checks"

    # Root check
    if [[ $EUID -ne 0 ]]; then
        log_fatal "This script must be run as root (use sudo ./setup.sh)"
    fi

    # Architecture check
    if [[ "$(uname -m)" != "x86_64" ]]; then
        log_fatal "This script requires x86_64 architecture (found: $(uname -m))"
    fi

    # Ubuntu 24.04 check
    if [[ -f /etc/os-release ]]; then
        local os_id os_version
        os_id=$(. /etc/os-release && echo "${ID:-}")
        os_version=$(. /etc/os-release && echo "${VERSION_ID:-}")

        if [[ "$os_id" != "ubuntu" ]]; then
            log_warn "This script is designed for Ubuntu (detected: ${os_id})"
            if ! prompt_yes_no "Continue anyway?" "no"; then
                exit 1
            fi
        elif [[ "$os_version" != "24.04" ]]; then
            log_warn "This script is designed for Ubuntu 24.04 (detected: ${os_version})"
            if ! prompt_yes_no "Continue anyway?" "no"; then
                exit 1
            fi
        fi
    else
        log_warn "Cannot detect OS version (/etc/os-release not found)"
        if ! prompt_yes_no "Continue anyway?" "no"; then
            exit 1
        fi
    fi

    log_info "Preflight checks passed"
}

# ============================================================================
# Collect all input before doing any work
# ============================================================================
collect_global_config() {
    log_step "Global Configuration"
    echo ""

    # Instance count
    local count
    while true; do
        count=$(prompt_value "Number of server instances" "4")
        validate_instance_count "$count" && break
    done
    INSTANCE_COUNT="$count"

    # Install directory
    local install_dir
    while true; do
        install_dir=$(prompt_value "CS2 install directory" "/opt/cs2")
        validate_directory_path "$install_dir" && break
    done
    INSTALL_DIR="$install_dir"

    # Service user
    local svc_user
    while true; do
        svc_user=$(prompt_value "Dedicated system user" "cs2")
        validate_username "$svc_user" && break
    done
    SERVICE_USER="$svc_user"

    # Public IP (auto-detect)
    local detected_ip=""
    detected_ip=$(curl -fsSL --connect-timeout 5 ifconfig.me 2>/dev/null || echo "")
    local public_ip
    while true; do
        public_ip=$(prompt_value "Server public IP" "${detected_ip}")
        validate_ip_address "$public_ip" && break
    done
    PUBLIC_IP="$public_ip"

    # eBot config
    local ebot_ip
    while true; do
        ebot_ip=$(prompt_value "eBot logs-receiver IP" "")
        if [[ -z "$ebot_ip" ]]; then
            log_error "eBot IP is required"
            continue
        fi
        validate_ip_address "$ebot_ip" && break
    done
    EBOT_IP="$ebot_ip"

    local ebot_port
    while true; do
        ebot_port=$(prompt_value "eBot logs-receiver port" "12345")
        validate_port "$ebot_port" && break
    done
    EBOT_PORT="$ebot_port"

    # eBot log address — the base URL that eBot's LOG_ADDRESS_SERVER is set to
    # Default matches eBot's default: http://IP:PORT
    local default_log_addr="http://${ebot_ip}:${ebot_port}"
    EBOT_LOG_ADDRESS=$(prompt_value "eBot log address base URL" "${default_log_addr}")

    # Metamod / CSay toggle
    if prompt_yes_no "Install Metamod + CounterStrikeSharp?" "yes"; then
        INSTALL_METAMOD="true"
        if prompt_yes_no "Install CSay plugin?" "yes"; then
            INSTALL_CSAY="true"
        else
            INSTALL_CSAY="false"
        fi
    else
        INSTALL_METAMOD="false"
        INSTALL_CSAY="false"
    fi

    echo ""
}

collect_instance_configs() {
    log_step "Per-Instance Configuration"
    echo ""

    # Arrays to hold per-instance config
    HOSTNAMES=()
    GSLTS=()
    RCON_PASSWORDS=()
    SERVER_PASSWORDS=()
    GOTV_ENABLED=()
    MAX_PLAYERS=()

    local i
    for (( i = 1; i <= INSTANCE_COUNT; i++ )); do
        echo -e "${BOLD}--- Server ${i} of ${INSTANCE_COUNT} ---${RESET}"

        # Hostname
        local hostname
        hostname=$(prompt_value "Server hostname" "CS2 Server ${i}")
        HOSTNAMES+=("$hostname")

        # GSLT
        local gslt
        while true; do
            gslt=$(prompt_value "GSLT token (App 730)" "")
            if [[ -z "$gslt" ]]; then
                log_error "GSLT token is required"
                continue
            fi
            validate_gslt_token "$gslt" && break
        done
        GSLTS+=("$gslt")

        # RCON password
        local default_rcon
        default_rcon=$(generate_password 24)
        local rcon
        rcon=$(prompt_value "RCON password" "${default_rcon}")
        RCON_PASSWORDS+=("$rcon")

        # Server password
        local svpass
        svpass=$(prompt_value "Server password (empty = public)" "")
        SERVER_PASSWORDS+=("$svpass")

        # GOTV
        local gotv
        if prompt_yes_no "Enable GOTV?" "yes"; then
            gotv="1"
        else
            gotv="0"
        fi
        GOTV_ENABLED+=("$gotv")

        # Max players
        local maxp
        maxp=$(prompt_value "Max players" "12")
        MAX_PLAYERS+=("$maxp")

        echo ""
    done
}

# ============================================================================
# Display summary and confirm
# ============================================================================
display_summary() {
    log_step "Configuration Summary"
    echo ""
    echo -e "${BOLD}Global Settings:${RESET}"
    echo "  Instances:     ${INSTANCE_COUNT}"
    echo "  Install dir:   ${INSTALL_DIR}"
    echo "  Service user:  ${SERVICE_USER}"
    echo "  Public IP:     ${PUBLIC_IP}"
    echo "  eBot:          ${EBOT_IP}:${EBOT_PORT}"
    echo "  eBot log URL:  ${EBOT_LOG_ADDRESS}"
    echo "  Metamod/CSS:   ${INSTALL_METAMOD}"
    echo "  CSay:          ${INSTALL_CSAY}"
    echo ""

    echo -e "${BOLD}Instance Details:${RESET}"
    printf "  %-10s %-25s %-12s %-12s %-12s\n" "Instance" "Hostname" "Game Port" "GOTV Port" "Max Players"
    printf "  %-10s %-25s %-12s %-12s %-12s\n" "--------" "--------" "---------" "---------" "-----------"

    local i game_port gotv_port
    for (( i = 0; i < INSTANCE_COUNT; i++ )); do
        game_port=$(calc_game_port $(( i + 1 )))
        gotv_port=$(calc_gotv_port $(( i + 1 )))
        printf "  %-10s %-25s %-12s %-12s %-12s\n" \
            "server-$(( i + 1 ))" \
            "${HOSTNAMES[$i]}" \
            "${game_port}" \
            "${gotv_port}" \
            "${MAX_PLAYERS[$i]}"
    done
    echo ""

    if ! prompt_yes_no "Proceed with installation?" "yes"; then
        log_info "Installation cancelled"
        exit 0
    fi
    echo ""
}

# ============================================================================
# Phase 1: System preparation
# ============================================================================
phase_system_prep() {
    log_step "Phase 1/9: System Preparation"

    # Enable i386 architecture
    if ! dpkg --print-foreign-architectures | grep -q i386; then
        dpkg --add-architecture i386
    fi

    # Update apt cache
    apt-get update -qq

    # Install dependencies
    if ! apt-get install -y -qq \
        lib32gcc-s1 lib32stdc++6 \
        curl wget tar unzip jq \
        tmux screen \
        ca-certificates; then
        log_error "Failed to install system dependencies"
        return 1
    fi

    log_info "System dependencies installed"
}

# ============================================================================
# Phase 2: Create service user
# ============================================================================
phase_create_user() {
    log_step "Phase 2/9: Creating service user"

    if id "${SERVICE_USER}" &>/dev/null; then
        log_info "User '${SERVICE_USER}' already exists"
    else
        useradd -r -m -d "${INSTALL_DIR}" -s /usr/sbin/nologin "${SERVICE_USER}"
        log_info "Created system user '${SERVICE_USER}'"
    fi

    mkdir -p "${INSTALL_DIR}"
}

# ============================================================================
# Phase 3: SteamCMD installation
# ============================================================================
phase_steamcmd() {
    log_step "Phase 3/9: SteamCMD Installation"
    install_steamcmd "${INSTALL_DIR}"
    fix_steamclient_symlink "${INSTALL_DIR}"
}

# ============================================================================
# Phase 4: CS2 installation
# ============================================================================
phase_cs2() {
    log_step "Phase 4/9: CS2 Dedicated Server Installation"
    update_cs2 "${INSTALL_DIR}"
    validate_cs2_install "${INSTALL_DIR}"
}

# ============================================================================
# Phase 5: Metamod + CounterStrikeSharp + CSay
# ============================================================================
phase_plugins() {
    if [[ "$INSTALL_METAMOD" != "true" ]]; then
        log_step "Phase 5/9: Skipping Metamod/CSS (disabled)"
        return 0
    fi

    log_step "Phase 5/9: Plugin Installation"
    install_all_plugins "${INSTALL_DIR}" "${INSTALL_CSAY}"
}

# ============================================================================
# Phase 6: Instance configuration
# ============================================================================
phase_instances() {
    log_step "Phase 6/9: Instance Configuration"

    # Remove old credentials file for fresh generation
    rm -f "${INSTALL_DIR}/instances/credentials.txt"

    local i idx
    for (( i = 1; i <= INSTANCE_COUNT; i++ )); do
        idx=$(( i - 1 ))
        setup_instance \
            "${INSTALL_DIR}" \
            "${i}" \
            "${TEMPLATE_DIR}" \
            "${HOSTNAMES[$idx]}" \
            "${GSLTS[$idx]}" \
            "${RCON_PASSWORDS[$idx]}" \
            "${SERVER_PASSWORDS[$idx]}" \
            "${GOTV_ENABLED[$idx]}" \
            "${MAX_PLAYERS[$idx]}" \
            "${PUBLIC_IP}" \
            "${EBOT_IP}" \
            "${EBOT_PORT}" \
            "${SERVICE_USER}" \
            "${EBOT_LOG_ADDRESS}"

        write_credentials_file \
            "${INSTALL_DIR}" \
            "${i}" \
            "${RCON_PASSWORDS[$idx]}" \
            "$(calc_game_port "$i")"
    done
}

# ============================================================================
# Phase 7: Ownership & permissions
# ============================================================================
phase_permissions() {
    log_step "Phase 7/9: Setting Ownership & Permissions"

    chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_DIR}"

    # Directories: 750, config files: 640
    find "${INSTALL_DIR}/instances" -type d -exec chmod 750 {} \;
    find "${INSTALL_DIR}/instances" -type f -exec chmod 640 {} \;

    # Credentials file: 600
    if [[ -f "${INSTALL_DIR}/instances/credentials.txt" ]]; then
        chmod 600 "${INSTALL_DIR}/instances/credentials.txt"
    fi

    # Log dirs writable
    find "${INSTALL_DIR}/logs" -type d -exec chmod 750 {} \;

    log_info "Permissions set"
}

# ============================================================================
# Phase 8: Service activation
# ============================================================================
phase_services() {
    log_step "Phase 8/9: Service Activation"

    systemctl daemon-reload

    local i
    for (( i = 1; i <= INSTANCE_COUNT; i++ )); do
        systemctl enable "cs2-server-${i}.service"
        log_info "Enabled cs2-server-${i}.service"
    done

    echo ""
    if prompt_yes_no "Start all servers now?" "no"; then
        for (( i = 1; i <= INSTANCE_COUNT; i++ )); do
            log_info "Starting cs2-server-${i}..."
            systemctl start "cs2-server-${i}.service"
            if (( i < INSTANCE_COUNT )); then
                sleep 5
            fi
        done
    fi
}

# ============================================================================
# Phase 9: Final summary
# ============================================================================
phase_summary() {
    log_step "Phase 9/9: Setup Complete"
    echo ""
    echo "=================================================================="
    echo "              CS2 Server Setup Complete"
    echo "=================================================================="
    echo ""

    printf "  %-10s %-12s %-12s %-12s %-24s\n" \
        "Instance" "Game Port" "GOTV Port" "Client Port" "RCON Password"
    printf "  %-10s %-12s %-12s %-12s %-24s\n" \
        "--------" "---------" "---------" "-----------" "-------------"

    local i idx game_port gotv_port client_port
    for (( i = 1; i <= INSTANCE_COUNT; i++ )); do
        idx=$(( i - 1 ))
        game_port=$(calc_game_port "$i")
        gotv_port=$(calc_gotv_port "$i")
        client_port=$(calc_client_port "$i")
        printf "  %-10s %-12s %-12s %-12s %-24s\n" \
            "server-${i}" \
            "${game_port}" \
            "${gotv_port}" \
            "${client_port}" \
            "${RCON_PASSWORDS[$idx]}"
    done

    echo ""
    echo "  eBot logs-receiver: ${EBOT_IP}:${EBOT_PORT}"
    echo ""
    echo "  Credentials saved to: ${INSTALL_DIR}/instances/credentials.txt"
    echo ""
    echo "  Commands:"
    echo "    Start all:    sudo systemctl start cs2-server-{1..${INSTANCE_COUNT}}"
    echo "    Stop all:     sudo systemctl stop cs2-server-{1..${INSTANCE_COUNT}}"
    echo "    Status:       sudo systemctl status 'cs2-server-*'"
    echo "    Update CS2:   sudo ${INSTALL_DIR}/scripts/update-servers.sh"
    echo "    View logs:    journalctl -u cs2-server-1 -f"
    echo "    Add instance: sudo ${INSTALL_DIR}/scripts/add-instance.sh"
    echo ""
    echo "=================================================================="
}

# ============================================================================
# Install helper scripts to the install directory
# ============================================================================
install_helper_scripts() {
    local scripts_dest="${INSTALL_DIR}/scripts"
    mkdir -p "${scripts_dest}"

    if [[ -d "${SCRIPT_DIR}/scripts" ]]; then
        cp "${SCRIPT_DIR}/scripts/"*.sh "${scripts_dest}/" 2>/dev/null || true
        chmod 755 "${scripts_dest}/"*.sh 2>/dev/null || true

        # Inject INSTALL_DIR into helper scripts
        local script
        for script in "${scripts_dest}/"*.sh; do
            [[ -f "$script" ]] || continue
            sed -i "s|%%INSTALL_DIR%%|${INSTALL_DIR}|g" "$script"
            sed -i "s|%%SERVICE_USER%%|${SERVICE_USER}|g" "$script"
        done
    fi
}

# ============================================================================
# Main
# ============================================================================
main() {
    echo ""
    echo -e "${BOLD}CS2 Dedicated Server Setup Script${RESET}"
    echo -e "ESL Pro Tour 2026 competitive defaults"
    echo ""

    preflight_checks
    collect_global_config
    collect_instance_configs
    display_summary

    phase_system_prep
    phase_create_user
    phase_steamcmd
    phase_cs2
    phase_plugins
    phase_instances
    phase_permissions
    install_helper_scripts
    phase_services
    phase_summary
}

main "$@"
