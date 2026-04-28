#!/usr/bin/env bash
# common.sh — Shared functions: logging, colors, prompts, utilities
# Source guard
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

set -euo pipefail

# ---------------------------------------------------------------------------
# Colors (disabled if stdout is not a terminal)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[0;33m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly BOLD='\033[1m'
    readonly RESET='\033[0m'
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_info()  { echo -e "${GREEN}[INFO]${RESET}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
log_step()  { echo -e "${BLUE}${BOLD}==>${RESET} ${BOLD}$*${RESET}"; }
log_fatal() { echo -e "${RED}${BOLD}[FATAL]${RESET} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# prompt_value — Prompt user for a value with an optional default
#
# Usage: result=$(prompt_value "Prompt text" "default_value")
#
# Returns the value via stdout. Uses stderr for the prompt so stdout
# is clean for capture.
# ---------------------------------------------------------------------------
prompt_value() {
    local prompt="$1"
    local default="${2:-}"
    local input

    if [[ -n "$default" ]]; then
        echo -ne "${CYAN}${prompt}${RESET} [${default}]: " >&2
    else
        echo -ne "${CYAN}${prompt}${RESET}: " >&2
    fi

    read -r input
    echo "${input:-$default}"
}

# ---------------------------------------------------------------------------
# prompt_yes_no — Prompt for yes/no, returns 0 for yes, 1 for no
#
# Usage: if prompt_yes_no "Enable feature?" "yes"; then ...
# ---------------------------------------------------------------------------
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-yes}"
    local input

    if [[ "$default" == "yes" ]]; then
        echo -ne "${CYAN}${prompt}${RESET} [Y/n]: " >&2
    else
        echo -ne "${CYAN}${prompt}${RESET} [y/N]: " >&2
    fi

    read -r input
    input="${input:-$default}"

    case "${input,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# generate_password — Generate a random alphanumeric password
#
# Usage: pass=$(generate_password 24)
# ---------------------------------------------------------------------------
generate_password() {
    local length="${1:-24}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

# ---------------------------------------------------------------------------
# check_bash_version — Require Bash 4.3+
# ---------------------------------------------------------------------------
check_bash_version() {
    local major minor
    major="${BASH_VERSINFO[0]}"
    minor="${BASH_VERSINFO[1]}"

    if (( major < 4 || (major == 4 && minor < 3) )); then
        log_fatal "Bash 4.3+ is required (found ${BASH_VERSION})"
    fi
}

# Run version check on source
check_bash_version
