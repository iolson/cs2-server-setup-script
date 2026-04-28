#!/usr/bin/env bash
# instance.sh — Per-instance setup: port calculation, template rendering,
#                config generation, systemd units, symlinks

[[ -n "${_INSTANCE_SH_LOADED:-}" ]] && return 0
_INSTANCE_SH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/firewall.sh"

# ---------------------------------------------------------------------------
# Port calculation — base port + (instance - 1) * 100
# ---------------------------------------------------------------------------
calc_game_port()   { echo $(( 27015 + ($1 - 1) * 100 )); }
calc_gotv_port()   { echo $(( 27020 + ($1 - 1) * 100 )); }
calc_client_port() { echo $(( 27005 + ($1 - 1) * 100 )); }

# ---------------------------------------------------------------------------
# render_template — Replace %%KEY%% placeholders in a template file
#
# Usage: render_template "template.tpl" "output_file" "KEY1=val1" "KEY2=val2"
#
# Uses | as sed delimiter to avoid conflicts with paths.
# Values are escaped for sed replacement.
# ---------------------------------------------------------------------------
render_template() {
    local template="$1"
    local output="$2"
    shift 2

    if [[ ! -f "$template" ]]; then
        log_error "Template not found: ${template}"
        return 1
    fi

    cp "$template" "$output"

    local pair key value
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        # Escape sed special characters in value
        value=$(printf '%s' "$value" | sed 's/[&/\]/\\&/g')
        sed -i "s|%%${key}%%|${value}|g" "$output"
    done
}

# ---------------------------------------------------------------------------
# handle_existing_config — Backup existing config, prompt for overwrite
#
# Usage: handle_existing_config "/path/to/file"
# Returns 0 if should proceed (overwrite), 1 if should skip
# ---------------------------------------------------------------------------
handle_existing_config() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        return 0
    fi

    local backup="${filepath}.bak.$(date +%Y%m%d_%H%M%S)"
    log_warn "Config already exists: ${filepath}"
    log_info "Backing up to: ${backup}"
    cp "$filepath" "$backup"

    if prompt_yes_no "Overwrite existing config?" "yes"; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# setup_instance — Create a single server instance
#
# Usage: setup_instance <install_dir> <instance_num> <template_dir> \
#            <hostname> <gslt> <rcon_pass> <server_pass> <gotv_enabled> \
#            <max_players> <public_ip> <ebot_ip> <ebot_port> \
#            <service_user> <ebot_log_address>
# ---------------------------------------------------------------------------
setup_instance() {
    local install_dir="$1"
    local instance_num="$2"
    local template_dir="$3"
    local hostname="$4"
    local gslt="$5"
    local rcon_pass="$6"
    local server_pass="$7"
    local gotv_enabled="$8"
    local max_players="$9"
    local public_ip="${10}"
    local ebot_ip="${11}"
    local ebot_port="${12}"
    local service_user="${13}"
    local ebot_log_address="${14:-http://${ebot_ip}:${ebot_port}}"

    local game_port gotv_port client_port
    game_port=$(calc_game_port "$instance_num")
    gotv_port=$(calc_gotv_port "$instance_num")
    client_port=$(calc_client_port "$instance_num")

    local instance_dir="${install_dir}/instances/server-${instance_num}"
    local cfg_dir="${instance_dir}/cfg"
    local log_dir="${install_dir}/logs/server-${instance_num}"
    local csgo_cfg_dir="${install_dir}/serverfiles/game/csgo/cfg"

    log_step "Setting up instance server-${instance_num} (port ${game_port})"

    # 1. Create directories
    mkdir -p "${cfg_dir}" "${log_dir}"

    # 2. Symlink: csgo/cfg/server-N -> instances/server-N/cfg
    ln -sfn "${cfg_dir}" "${csgo_cfg_dir}/server-${instance_num}"

    # 3. Render server.cfg
    if handle_existing_config "${cfg_dir}/server.cfg"; then
        render_template "${template_dir}/server.cfg.tpl" "${cfg_dir}/server.cfg" \
            "INSTANCE_NUM=${instance_num}" \
            "HOSTNAME=${hostname}" \
            "GSLT_TOKEN=${gslt}" \
            "RCON_PASSWORD=${rcon_pass}" \
            "SERVER_PASSWORD=${server_pass}" \
            "GOTV_ENABLED=${gotv_enabled}" \
            "GOTV_PORT=${gotv_port}" \
            "GAME_PORT=${game_port}" \
            "PUBLIC_IP=${public_ip}" \
            "EBOT_IP=${ebot_ip}" \
            "EBOT_PORT=${ebot_port}" \
            "EBOT_LOG_ADDRESS=${ebot_log_address}"
    fi

    # 4. Render autoexec.cfg
    if handle_existing_config "${cfg_dir}/autoexec.cfg"; then
        render_template "${template_dir}/autoexec.cfg.tpl" "${cfg_dir}/autoexec.cfg" \
            "INSTANCE_NUM=${instance_num}"
    fi

    # 5. Write instance.env
    cat > "${instance_dir}/instance.env" <<ENVEOF
# Instance environment — server-${instance_num}
# Generated by cs2-server-setup-script
CS2_INSTANCE=${instance_num}
CS2_HOSTNAME=${hostname}
CS2_GAME_PORT=${game_port}
CS2_GOTV_PORT=${gotv_port}
CS2_CLIENT_PORT=${client_port}
CS2_RCON_PASSWORD=${rcon_pass}
CS2_SERVER_PASSWORD=${server_pass}
CS2_GSLT_TOKEN=${gslt}
CS2_PUBLIC_IP=${public_ip}
CS2_EBOT_IP=${ebot_ip}
CS2_EBOT_PORT=${ebot_port}
CS2_EBOT_LOG_ADDRESS=${ebot_log_address}
CS2_MAX_PLAYERS=${max_players}
CS2_GOTV_ENABLED=${gotv_enabled}
ENVEOF

    # 6. Render systemd unit
    render_template "${template_dir}/cs2-server.service.tpl" \
        "/etc/systemd/system/cs2-server-${instance_num}.service" \
        "INSTANCE_NUM=${instance_num}" \
        "INSTALL_DIR=${install_dir}" \
        "GAME_PORT=${game_port}" \
        "CLIENT_PORT=${client_port}" \
        "GOTV_PORT=${gotv_port}" \
        "MAX_PLAYERS=${max_players}" \
        "SERVICE_USER=${service_user}"

    # 7. Firewall rules
    configure_ufw_for_instance "${game_port}" "${gotv_port}"

    log_info "Instance server-${instance_num} configured"
}

# ---------------------------------------------------------------------------
# write_credentials_file — Append instance credentials
#
# Usage: write_credentials_file "/opt/cs2" 1 "rcon_pass" 27015
# ---------------------------------------------------------------------------
write_credentials_file() {
    local install_dir="$1"
    local instance_num="$2"
    local rcon_pass="$3"
    local game_port="$4"
    local creds_file="${install_dir}/instances/credentials.txt"

    # Write header on first call
    if [[ ! -f "$creds_file" ]]; then
        cat > "$creds_file" <<'HEADER'
# CS2 Server Credentials
# Generated by cs2-server-setup-script
# Keep this file secure — it contains RCON passwords
# ========================================================
HEADER
        chmod 600 "$creds_file"
    fi

    cat >> "$creds_file" <<CRED

[server-${instance_num}]
game_port=${game_port}
rcon_password=${rcon_pass}
CRED
}

# ---------------------------------------------------------------------------
# recreate_instance_symlinks — Re-create cfg symlinks after SteamCMD updates
#
# Usage: recreate_instance_symlinks "/opt/cs2"
# ---------------------------------------------------------------------------
recreate_instance_symlinks() {
    local install_dir="$1"
    local csgo_cfg_dir="${install_dir}/serverfiles/game/csgo/cfg"
    local instances_dir="${install_dir}/instances"

    if [[ ! -d "$instances_dir" ]]; then
        return 0
    fi

    local dir instance_num
    for dir in "${instances_dir}"/server-*/; do
        [[ -d "$dir" ]] || continue
        instance_num=$(basename "$dir" | sed 's/server-//')
        if [[ -d "${dir}cfg" ]]; then
            ln -sfn "${dir}cfg" "${csgo_cfg_dir}/server-${instance_num}"
            log_info "Recreated symlink for server-${instance_num}"
        fi
    done
}
