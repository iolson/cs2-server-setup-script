# PRD: Interactive CS2 Dedicated Server Setup Script

## Overview

An interactive Bash setup script that automates the installation and configuration of N Counter-Strike 2 dedicated server instances on a bare-metal Ubuntu Server 24.04 LTS machine. The servers are configured to work with [eBot](https://docs.esport-tools.net/introduction/getting-started) (managed via a separate Docker Compose repository) for competitive match management via RCON and log forwarding.

**Default configuration:** 4 server instances.

**Repository:** Open source (MIT or Apache 2.0 license).

---

## Goals

1. Reduce CS2 server provisioning from hours of manual work to a single interactive script run.
2. Support N configurable server instances sharing a single SteamCMD base installation.
3. Pre-configure all servers for eBot integration (RCON, log forwarding, GOTV, Metamod + CounterStrikeSharp + CSay plugin).
4. Produce systemd services for each instance so servers survive reboots and can be managed individually.
5. Be idempotent — safe to re-run for updates or adding additional instances.

## Non-Goals

- eBot Web UI / eBot application / logs-receiver / Redis / MySQL installation (handled in a separate Docker Compose repository).
- Windows or macOS support.
- Docker-based CS2 server deployment (this is bare-metal only).
- Full CS2 game-mode configuration (practice configs, workshop maps, etc.) — only competitive/eBot defaults.

---

## Target Environment

| Component | Requirement |
|---|---|
| OS | Ubuntu Server 24.04 LTS (fresh or existing) |
| Architecture | x86_64 |
| RAM | Minimum 4 GB per instance (16 GB+ recommended for 4 servers) |
| Disk | 40 GB for shared base install + ~2 GB per additional instance (SSD strongly recommended) |
| Network | Static IP or known IP; ports open per instance (see Port Scheme) |
| User | Runs as root; creates a dedicated `cs2` system user for runtime |

---

## Architecture

### Directory Layout

```
/opt/cs2/
├── steamcmd/                    # SteamCMD installation
├── serverfiles/                 # Shared base CS2 installation (app 730)
│   └── game/csgo/
│       ├── addons/
│       │   ├── metamod/         # Metamod:Source (shared)
│       │   └── counterstrikesharp/  # CounterStrikeSharp (shared)
│       └── gameinfo.gi          # Patched for Metamod
├── instances/
│   ├── server-1/
│   │   ├── cfg/
│   │   │   ├── server.cfg
│   │   │   ├── autoexec.cfg
│   │   │   └── gamemode_competitive.cfg
│   │   ├── csay.cfg             # CSay plugin config (if applicable)
│   │   └── instance.env         # Instance-specific environment vars
│   ├── server-2/
│   ├── server-3/
│   └── server-4/
├── scripts/
│   ├── update-servers.sh        # SteamCMD update all instances
│   ├── add-instance.sh          # Add a new server instance
│   └── remove-instance.sh       # Remove a server instance
└── logs/
    ├── server-1/
    ├── server-2/
    ├── server-3/
    └── server-4/
```

### Shared vs. Per-Instance Files

- **Shared (read-only at runtime):** SteamCMD, CS2 base game files (`/opt/cs2/serverfiles/`), Metamod binaries, CounterStrikeSharp binaries.
- **Per-Instance (writable):** `server.cfg`, launch parameters, GSLT token, RCON password, log directory, GOTV config. Achieved via symlinks or `-usercon` style overlay — instances reference the shared base but maintain their own `cfg/` directory.

---

## Port Scheme

Each instance uses a base port offset of **100** from the previous instance:

| Instance | Game Port (UDP/TCP) | GOTV Port (UDP) | Client Port (UDP) | RCON (TCP) |
|---|---|---|---|---|
| server-1 | 27015 | 27020 | 27005 | 27015 |
| server-2 | 27115 | 27120 | 27105 | 27115 |
| server-3 | 27215 | 27220 | 27205 | 27215 |
| server-4 | 27315 | 27320 | 27305 | 27315 |
| server-N | 27015 + (N-1)*100 | 27020 + (N-1)*100 | 27005 + (N-1)*100 | 27015 + (N-1)*100 |

The script will automatically calculate ports based on instance number.

---

## Interactive Prompts

The setup script will prompt for the following (with sane defaults):

### Global Configuration

| Prompt | Default | Notes |
|---|---|---|
| Number of server instances | `4` | Validated as integer >= 1 |
| CS2 install directory | `/opt/cs2` | Must have sufficient disk space |
| Dedicated system user | `cs2` | Created if doesn't exist |
| Server public IP | Auto-detected | Used for log forwarding and GOTV |
| eBot logs-receiver IP | (required) | IP/hostname of machine running eBot Docker stack |
| eBot logs-receiver port | `12345` | Default eBot logs-receiver port |
| Install Metamod + CounterStrikeSharp | `yes` | Required for CSay plugin |
| Install CSay plugin | `yes` | Required for full eBot functionality |
| Auto-update CS2 on service restart | `no` | Adds SteamCMD update to systemd ExecStartPre |

### Per-Instance Configuration

| Prompt | Default | Notes |
|---|---|---|
| Server hostname | `CS2 Server N` | `sv_hostname` |
| GSLT token | (required) | One per instance; generated at [Steam GSLT page](https://steamcommunity.com/dev/managegameservers) with App ID `730` |
| RCON password | Random 24-char | Unique per instance; needed for eBot |
| Server password | (empty) | `sv_password`; empty = public |
| GOTV enabled | `yes` | `tv_enable 1` |
| Max players | `12` | Standard competitive 5v5 + coaches + spectators |
| Tickrate | `128` | CS2 sub-tick; kept for compatibility |
| Game mode | `competitive` | `game_type 0; game_mode 1` |

### Confirmation

Before executing, the script displays a summary table of all configuration and asks for confirmation.

---

## What the Script Does

### Phase 1: System Preparation

1. Validate running on Ubuntu 24.04 x86_64 as root.
2. Update apt package cache.
3. Install dependencies:
   - `lib32gcc-s1`, `lib32stdc++6` (SteamCMD 32-bit deps)
   - `curl`, `wget`, `tar`, `unzip`, `jq`, `tmux`, `screen`
   - `ufw` (if firewall management is opted in)
4. Enable `i386` architecture if not already enabled.
5. Create `cs2` system user with home at `/opt/cs2` and no login shell.

### Phase 2: SteamCMD Installation

1. Download and extract SteamCMD to `/opt/cs2/steamcmd/`.
2. Run initial SteamCMD update.
3. Create symlink for `steamclient.so` to suppress runtime warnings.

### Phase 3: CS2 Base Installation

1. Install/update CS2 dedicated server (App ID `730`) to `/opt/cs2/serverfiles/` via SteamCMD anonymous login.
2. Validate installation.

### Phase 4: Metamod + CounterStrikeSharp Installation

1. Fetch latest stable Metamod:Source 2.x release for Linux from GitHub.
2. Extract to `/opt/cs2/serverfiles/game/csgo/addons/`.
3. Patch `gameinfo.gi` to load Metamod (add `Game csgo/addons/metamod` entry).
4. Fetch latest stable CounterStrikeSharp with runtime for Linux from GitHub.
5. Extract to `/opt/cs2/serverfiles/game/csgo/`.
6. Download and install CSay plugin to the CounterStrikeSharp plugins directory.

### Phase 5: Instance Configuration

For each instance (1..N):

1. Create instance directory at `/opt/cs2/instances/server-N/`.
2. Create log directory at `/opt/cs2/logs/server-N/`.
3. Generate `server.cfg`:

```cfg
// Server Identity
sv_hostname "{{ hostname }}"
sv_setsteamaccount "{{ gslt_token }}"
sv_password "{{ server_password }}"

// Network
sv_lan 0
sv_maxrate 0
sv_minrate 128000
sv_maxcmdrate 128
sv_mincmdrate 128

// RCON
rcon_password "{{ rcon_password }}"

// Logging (for eBot)
log on
sv_logflush 1
sv_logfile 1
mp_logdetail 3
mp_logmoney 1

// Log forwarding to eBot logs-receiver
logaddress_add_http "http://{{ ebot_logs_receiver_ip }}:{{ ebot_logs_receiver_port }}/log/{{ server_public_ip }}:{{ game_port }}"

// GOTV
tv_enable {{ gotv_enabled }}
tv_name "GOTV - {{ hostname }}"
tv_title "{{ hostname }}"
tv_port {{ gotv_port }}
tv_maxclients 32
tv_maxrate 0
tv_delay 30
tv_delaymapchange 1

// Competitive Defaults
mp_autoteambalance 0
mp_limitteams 0
mp_friendlyfire 1
mp_overtime_enable 1
sv_alltalk 0
sv_deadtalk 0
```

4. Generate `instance.env` with all instance-specific variables.
5. Generate systemd service file at `/etc/systemd/system/cs2-server-N.service`:

```ini
[Unit]
Description=CS2 Dedicated Server - Instance N
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=cs2
Group=cs2
WorkingDirectory=/opt/cs2/serverfiles
ExecStartPre=/bin/bash -c 'source /opt/cs2/instances/server-N/instance.env'
ExecStart=/opt/cs2/serverfiles/game/bin/linuxsteamrt64/cs2 \
    -dedicated \
    -console \
    -usercon \
    -port {{ game_port }} \
    +clientport {{ client_port }} \
    +tv_port {{ gotv_port }} \
    +game_type 0 \
    +game_mode 1 \
    +mapgroup mg_active \
    +map de_dust2 \
    +servercfgfile /opt/cs2/instances/server-N/cfg/server.cfg \
    -maxplayers {{ max_players }} \
    -ip 0.0.0.0
Restart=on-failure
RestartSec=15
StandardOutput=append:/opt/cs2/logs/server-N/console.log
StandardError=append:/opt/cs2/logs/server-N/error.log
LimitNOFILE=100000

[Install]
WantedBy=multi-user.target
```

### Phase 6: Firewall Configuration

If UFW is enabled, open ports for each instance:
- `{{ game_port }}/tcp`
- `{{ game_port }}/udp`
- `{{ gotv_port }}/udp`

### Phase 7: Ownership & Permissions

1. `chown -R cs2:cs2 /opt/cs2/`
2. Set appropriate permissions (750 for directories, 640 for config files).

### Phase 8: Service Activation

1. `systemctl daemon-reload`
2. `systemctl enable cs2-server-{1..N}`
3. Prompt: Start servers now? (y/n)
4. If yes, start all instances sequentially with a 5-second delay between each.

### Phase 9: Summary Output

Display a summary table:

```
╔══════════════════════════════════════════════════════════════════╗
║                    CS2 Server Setup Complete                     ║
╠══════════════════════════════════════════════════════════════════╣
║ Instance   │ Game Port │ RCON Port │ GOTV Port │ RCON Password  ║
╠════════════╪═══════════╪═══════════╪═══════════╪════════════════╣
║ server-1   │ 27015     │ 27015     │ 27020     │ ************   ║
║ server-2   │ 27115     │ 27115     │ 27120     │ ************   ║
║ server-3   │ 27215     │ 27215     │ 27220     │ ************   ║
║ server-4   │ 27315     │ 27315     │ 27320     │ ************   ║
╚══════════════════════════════════════════════════════════════════╝

eBot Configuration (add these to your eBot setup):
  Logs-receiver: {{ ebot_logs_receiver_ip }}:{{ ebot_logs_receiver_port }}

Credentials saved to: /opt/cs2/instances/credentials.txt (chmod 600)

Commands:
  Start all:    sudo systemctl start cs2-server-{1..4}
  Stop all:     sudo systemctl stop cs2-server-{1..4}
  Status:       sudo systemctl status cs2-server-*
  Update CS2:   sudo -u cs2 /opt/cs2/scripts/update-servers.sh
  View logs:    journalctl -u cs2-server-1 -f
  Add instance: sudo /opt/cs2/scripts/add-instance.sh
```

---

## Helper Scripts

### `update-servers.sh`

1. Stop all running CS2 instances.
2. Run SteamCMD to update App 730.
3. Re-apply Metamod `gameinfo.gi` patch if overwritten by update.
4. Restart all previously-running instances.

### `add-instance.sh`

1. Detect next available instance number.
2. Run interactive prompts for the new instance only.
3. Create instance directory, config, systemd service.
4. Open firewall ports.
5. Enable and optionally start the new instance.

### `remove-instance.sh`

1. Accept instance number as argument.
2. Stop and disable the systemd service.
3. Remove firewall rules.
4. Archive (not delete) instance config to `/opt/cs2/instances/.archive/`.
5. Remove systemd service file.

---

## eBot Integration Details

The CS2 servers are configured to forward logs to the eBot logs-receiver over HTTP. The eBot stack (running in Docker on a separate machine or the same machine) connects back to each CS2 server via RCON to manage matches.

### What CS2 servers provide to eBot:

| Data | Mechanism |
|---|---|
| Game logs (kills, rounds, etc.) | HTTP log forwarding to eBot logs-receiver (`logaddress_add_http`) |
| Server control | RCON (eBot connects to each server's RCON port with the configured password) |
| GOTV demos | Stored locally; eBot can trigger recording via RCON |

### What the eBot Docker stack needs to know (output by this script):

- Each server's IP + game port
- Each server's RCON password
- Logs-receiver must be accessible from CS2 servers on port 12345

### CSay Plugin

The CSay plugin for CounterStrikeSharp provides additional RCON commands that eBot uses for in-game messages and server control. It requires Metamod and CounterStrikeSharp to be installed (handled in Phase 4).

---

## Idempotency & Re-runs

The script must be safe to re-run:

- SteamCMD and CS2 files: `app_update 730 validate` is inherently idempotent.
- System user creation: Skip if user exists.
- Package installation: `apt install` is idempotent.
- Config files: Prompt to overwrite or skip if existing config detected.
- Systemd services: Overwrite and reload.
- Metamod `gameinfo.gi` patch: Check before applying.

---

## File Structure of This Repository

```
cs2-server-setup-script/
├── README.md                  # Usage instructions, prerequisites, quickstart
├── LICENSE                    # Open source license
├── setup.sh                   # Main interactive setup script (entry point)
├── lib/
│   ├── common.sh              # Shared functions (logging, colors, prompts)
│   ├── validation.sh          # Input validation functions
│   ├── steamcmd.sh            # SteamCMD install/update functions
│   ├── cs2.sh                 # CS2 server install/configure functions
│   ├── metamod.sh             # Metamod + CounterStrikeSharp install
│   ├── instance.sh            # Per-instance setup (config, systemd, firewall)
│   └── firewall.sh            # UFW rule management
├── templates/
│   ├── server.cfg.tpl         # server.cfg template with placeholders
│   ├── cs2-server.service.tpl # systemd unit template
│   └── autoexec.cfg.tpl       # autoexec.cfg template
├── scripts/
│   ├── update-servers.sh      # Update CS2 + plugins
│   ├── add-instance.sh        # Add new instance interactively
│   └── remove-instance.sh     # Remove/archive an instance
├── .editorconfig
└── .shellcheckrc              # ShellCheck configuration
```

---

## Technical Decisions

| Decision | Rationale |
|---|---|
| Bash (not Python/Ansible) | Zero additional dependencies on a fresh Ubuntu server; target audience is server admins comfortable with shell |
| Bare-metal (not Docker) for CS2 | Game servers benefit from direct hardware access; avoids Docker overhead for high-tick-rate servers; simplifies port management |
| Shared base install with per-instance configs | Saves ~35 GB disk per additional instance; single update point |
| systemd services | Native process management; auto-restart; journald logging; boot integration |
| Port offset of 100 | Industry convention for CS2 multi-server; avoids port collisions between game/GOTV/client ports |
| Separate eBot Docker repo | eBot has complex dependencies (PHP 7.4, MySQL, Redis, Node.js, Nginx); containerization isolates these; CS2 servers don't need any of them |

---

## Security Considerations

- RCON passwords are randomly generated (24 chars, alphanumeric) and stored in a `chmod 600` credentials file.
- The `cs2` user has no login shell (`/usr/sbin/nologin`) and no sudo access.
- Config files are `chmod 640` owned by `cs2:cs2`.
- Firewall rules are scoped to only the required ports per instance.
- GSLT tokens are stored only in instance configs (not logged or displayed after initial setup).

---

## Future Considerations (Out of Scope for v1)

- Automated GSLT token generation via Steam Web API.
- Log rotation configuration for console logs.
- Backup/restore scripts for instance configurations.
- Monitoring integration (Prometheus node exporter metrics).
- Auto-update cron job for CS2 and plugins.
- Support for custom game modes beyond competitive.
- Workshop map collection management.
