#!/usr/bin/env bash
# metamod.sh — Metamod:Source, CounterStrikeSharp, and CSay installation

[[ -n "${_METAMOD_SH_LOADED:-}" ]] && return 0
_METAMOD_SH_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ---------------------------------------------------------------------------
# get_latest_github_release — Get the latest release download URL from GitHub
#
# Usage: url=$(get_latest_github_release "owner/repo" "pattern")
# pattern: grep -E pattern to match the desired asset filename
# ---------------------------------------------------------------------------
get_latest_github_release() {
    local repo="$1"
    local pattern="$2"
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local response

    response=$(curl -fsSL -w "\n%{http_code}" "${api_url}" 2>/dev/null) || true
    local http_code
    http_code=$(echo "$response" | tail -n1)
    response=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "403" ]]; then
        log_error "GitHub API rate limit reached. Try again later or set GITHUB_TOKEN."
        return 1
    fi

    if [[ "$http_code" != "200" ]]; then
        log_error "Failed to fetch latest release from ${repo} (HTTP ${http_code})"
        return 1
    fi

    local url
    url=$(echo "$response" | jq -r ".assets[] | select(.name | test(\"${pattern}\")) | .browser_download_url" | head -n1)

    if [[ -z "$url" || "$url" == "null" ]]; then
        log_error "No asset matching '${pattern}' found in latest release of ${repo}"
        return 1
    fi

    echo "$url"
}

# ---------------------------------------------------------------------------
# download_and_extract — Download an archive and extract it
#
# Usage: download_and_extract "https://..." "/target/dir"
# Supports .zip and .tar.gz
# ---------------------------------------------------------------------------
download_and_extract() {
    local url="$1"
    local target_dir="$2"
    local tmpfile

    tmpfile=$(mktemp)
    trap 'rm -f "${tmpfile}"' RETURN

    log_info "Downloading: ${url}"
    curl -fsSL -o "${tmpfile}" "${url}"

    mkdir -p "${target_dir}"

    if [[ "$url" == *.zip ]]; then
        unzip -qo "${tmpfile}" -d "${target_dir}"
    elif [[ "$url" == *.tar.gz ]] || [[ "$url" == *.tgz ]]; then
        tar -xzf "${tmpfile}" -C "${target_dir}"
    else
        log_error "Unsupported archive format: ${url}"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# install_metamod — Fetch and install latest Metamod:Source
#
# Usage: install_metamod "/opt/cs2"
# ---------------------------------------------------------------------------
install_metamod() {
    local install_dir="$1"
    local csgo_dir="${install_dir}/serverfiles/game/csgo"
    local url

    log_step "Installing Metamod:Source"

    url=$(get_latest_github_release "alliedmodders/metamod-source" "mmsource-.*-linux\\.tar\\.gz") || {
        log_error "Failed to get Metamod:Source download URL"
        return 1
    }

    download_and_extract "${url}" "${csgo_dir}"
    log_info "Metamod:Source installed to ${csgo_dir}/addons/metamod/"
}

# ---------------------------------------------------------------------------
# patch_gameinfo — Add Metamod entry to gameinfo.gi (idempotent)
#
# Usage: patch_gameinfo "/opt/cs2"
# ---------------------------------------------------------------------------
patch_gameinfo() {
    local install_dir="$1"
    local gameinfo="${install_dir}/serverfiles/game/csgo/gameinfo.gi"

    if [[ ! -f "${gameinfo}" ]]; then
        log_error "gameinfo.gi not found at ${gameinfo}"
        return 1
    fi

    if grep -q "csgo/addons/metamod" "${gameinfo}"; then
        log_info "gameinfo.gi already patched for Metamod"
        return 0
    fi

    log_step "Patching gameinfo.gi for Metamod"
    sed -i "/Game_LowViolence/a\\\\t\\t\\tGame\\tcsgo/addons/metamod" "${gameinfo}"
    log_info "gameinfo.gi patched successfully"
}

# ---------------------------------------------------------------------------
# install_counterstrikesharp — Fetch and install latest CSS with runtime
#
# Usage: install_counterstrikesharp "/opt/cs2"
# ---------------------------------------------------------------------------
install_counterstrikesharp() {
    local install_dir="$1"
    local csgo_dir="${install_dir}/serverfiles/game/csgo"
    local url

    log_step "Installing CounterStrikeSharp"

    url=$(get_latest_github_release "roflmuffin/CounterStrikeSharp" "counterstrikesharp-with-runtime-build-.*-linux\\.zip") || {
        log_error "Failed to get CounterStrikeSharp download URL"
        return 1
    }

    download_and_extract "${url}" "${csgo_dir}"
    log_info "CounterStrikeSharp installed to ${csgo_dir}/addons/counterstrikesharp/"
}

# ---------------------------------------------------------------------------
# install_csay — Download CSay plugin from esport-tools.net
#
# Usage: install_csay "/opt/cs2"
# ---------------------------------------------------------------------------
install_csay() {
    local install_dir="$1"
    local plugins_dir="${install_dir}/serverfiles/game/csgo/addons/counterstrikesharp/plugins"
    local csay_url="https://esport-tools.net/download/CSay-CS2.zip"
    local tmpfile

    log_step "Installing CSay plugin"

    tmpfile=$(mktemp)
    trap 'rm -f "${tmpfile}"' RETURN

    local http_code
    http_code=$(curl -fsSL -o "${tmpfile}" -w "%{http_code}" "${csay_url}" 2>/dev/null) || true

    if [[ "$http_code" != "200" ]]; then
        log_error "Failed to download CSay plugin (HTTP ${http_code}). You may need to install it manually."
        log_error "Download URL: ${csay_url}"
        return 1
    fi

    mkdir -p "${plugins_dir}"
    unzip -qo "${tmpfile}" -d "${plugins_dir}"
    log_info "CSay plugin installed to ${plugins_dir}/CSay/"
}

# ---------------------------------------------------------------------------
# install_all_plugins — Install Metamod + CSS + CSay (full stack)
#
# Usage: install_all_plugins "/opt/cs2" [install_csay=true]
# ---------------------------------------------------------------------------
install_all_plugins() {
    local install_dir="$1"
    local with_csay="${2:-true}"

    install_metamod "${install_dir}"
    patch_gameinfo "${install_dir}"
    install_counterstrikesharp "${install_dir}"

    if [[ "$with_csay" == "true" ]]; then
        install_csay "${install_dir}"
    fi
}
