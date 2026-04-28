#!/usr/bin/env bash
# validation.sh — Input validation functions
# Each returns 0 on success, 1 on failure. Prints error on failure. Never exits.

[[ -n "${_VALIDATION_SH_LOADED:-}" ]] && return 0
_VALIDATION_SH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---------------------------------------------------------------------------
# validate_instance_count — Must be a positive integer
# ---------------------------------------------------------------------------
validate_instance_count() {
    local value="$1"
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        log_error "Instance count must be a positive integer (got: '${value}')"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# validate_ip_address — Basic IPv4 validation
# ---------------------------------------------------------------------------
validate_ip_address() {
    local ip="$1"
    local octet="(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)"
    if [[ ! "$ip" =~ ^${octet}\.${octet}\.${octet}\.${octet}$ ]]; then
        log_error "Invalid IPv4 address: '${ip}'"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# validate_port — Must be 1-65535
# ---------------------------------------------------------------------------
validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        log_error "Port must be between 1 and 65535 (got: '${port}')"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# validate_directory_path — Must be an absolute path
# ---------------------------------------------------------------------------
validate_directory_path() {
    local path="$1"
    if [[ ! "$path" =~ ^/ ]]; then
        log_error "Directory path must be absolute (got: '${path}')"
        return 1
    fi
    if [[ "$path" =~ [[:space:]] ]]; then
        log_error "Directory path must not contain spaces (got: '${path}')"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# validate_gslt_token — Must be a 32-character hex string
# ---------------------------------------------------------------------------
validate_gslt_token() {
    local token="$1"
    if [[ ! "$token" =~ ^[A-Fa-f0-9]{32}$ ]]; then
        log_error "GSLT token must be a 32-character hex string (got: '${token}')"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# validate_username — Must be a valid Linux username
# ---------------------------------------------------------------------------
validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        log_error "Username must start with a lowercase letter or underscore, followed by lowercase alphanumeric, underscore, or hyphen (got: '${username}')"
        return 1
    fi
    if (( ${#username} > 32 )); then
        log_error "Username must be 32 characters or fewer (got: ${#username})"
        return 1
    fi
    return 0
}
