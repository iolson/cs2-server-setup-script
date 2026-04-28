# CS2 Server Setup Script

An interactive Bash script that provisions **N** Counter-Strike 2 dedicated server instances on Ubuntu 24.04 LTS bare metal. Designed for LAN tournament organizers using [eBot](https://docs.esport-tools.net/introduction/getting-started) for match management.

Default server configs follow the **ESL Pro Tour 2026** competitive ruleset (Section 2.4).

## What This Does

- Installs SteamCMD and CS2 dedicated server (shared base install)
- Installs Metamod:Source, CounterStrikeSharp, and CSay plugin
- Creates N independent server instances with per-instance configs
- Sets up systemd services for each instance (auto-restart, boot integration)
- Configures UFW firewall rules per instance
- Pre-configures eBot log forwarding and RCON access
- Generates random RCON passwords and saves credentials securely

## What This Does NOT Do

- Install or configure the eBot stack (web UI, logs-receiver, MySQL, Redis) — use the separate [eBot Docker Compose repo](https://docs.esport-tools.net/introduction/getting-started) for that
- Support Windows or macOS
- Run CS2 servers in Docker containers

## Prerequisites

- **OS:** Ubuntu Server 24.04 LTS (x86_64)
- **RAM:** 4 GB per instance minimum (16 GB+ recommended for 4 servers)
- **Disk:** 40 GB for base install + ~2 GB per additional instance (SSD recommended)
- **Network:** Static or known IP, with required ports accessible
- **GSLT tokens:** One per server instance — generate at [Steam GSLT](https://steamcommunity.com/dev/managegameservers) with App ID `730`
- **eBot stack** running and accessible (for log forwarding)

## Quickstart

```bash
git clone https://github.com/your-org/cs2-server-setup-script.git
cd cs2-server-setup-script
sudo ./setup.sh
```

The script will interactively prompt for all configuration. Defaults are sane for a 4-server competitive LAN setup.

## Port Scheme

Each instance is offset by 100 from the previous:

| Instance | Game Port (UDP/TCP) | Client Port (UDP) | GOTV Port (UDP) |
|----------|--------------------|--------------------|-----------------|
| server-1 | 27015 | 27005 | 27020 |
| server-2 | 27115 | 27105 | 27120 |
| server-3 | 27215 | 27205 | 27220 |
| server-4 | 27315 | 27305 | 27320 |
| server-N | 27015 + (N-1)\*100 | 27005 + (N-1)\*100 | 27020 + (N-1)\*100 |

## ESL Pro Tour 2026 Defaults

The `server.cfg` template includes competitive match settings from the ESL Pro Tour 2026 ruleset (Section 2.4):

| Setting | Value | CVar |
|---------|-------|------|
| Max rounds | 24 (MR12) | `mp_maxrounds 24` |
| Round time | 1:55 | `mp_roundtime 1.92` |
| Start money | $800 | `mp_startmoney 800` |
| Freeze time | 20s | `mp_freezetime 20` |
| Buy time | 20s | `mp_buytime 20` |
| C4 timer | 40s | `mp_c4timer 40` |
| OT rounds | 6 (MR3) | `mp_overtime_maxrounds 6` |
| OT start money | $12,500 | `mp_overtime_startmoney 12500` |
| Round restart delay | 5s | `mp_round_restart_delay 5` |
| Friendly fire | On | `mp_friendlyfire 1` |
| Overtime | Enabled | `mp_overtime_enable 1` |

## eBot Integration

The CS2 servers are configured to work with eBot out of the box:

- **Log forwarding:** Each server sends game logs to the eBot logs-receiver via `logaddress_add_http`
- **RCON:** eBot connects to each server's RCON port to manage matches
- **GOTV:** Enabled by default for demo recording
- **CSay plugin:** Provides additional RCON commands for in-game messages

### What eBot needs from these servers

| Data | How |
|------|-----|
| Each server's IP + game port | Displayed in setup summary |
| Each server's RCON password | Saved to `/opt/cs2/instances/credentials.txt` |
| Logs-receiver accessibility | CS2 servers must reach eBot logs-receiver on port 12345 |

## Directory Layout

```
/opt/cs2/
├── steamcmd/                        # SteamCMD installation
├── serverfiles/                     # Shared CS2 base install
│   └── game/csgo/
│       ├── addons/metamod/          # Metamod:Source
│       ├── addons/counterstrikesharp/  # CounterStrikeSharp
│       └── cfg/server-N/            # Symlink → /opt/cs2/instances/server-N/cfg/
├── instances/
│   ├── server-1/
│   │   ├── cfg/server.cfg           # Per-instance config
│   │   ├── cfg/autoexec.cfg
│   │   └── instance.env             # Environment variables
│   ├── server-2/
│   └── ...
├── logs/
│   ├── server-1/
│   └── ...
└── scripts/                         # Installed helper scripts
```

## Helper Scripts

After setup, these scripts are available:

### Update all servers

```bash
sudo /opt/cs2/scripts/update-servers.sh
```

Stops running servers, updates CS2 via SteamCMD, re-patches Metamod, restarts previously-running servers.

### Add a new instance

```bash
sudo /opt/cs2/scripts/add-instance.sh
```

Detects the next instance number, prompts for configuration, creates everything needed.

### Remove an instance

```bash
sudo /opt/cs2/scripts/remove-instance.sh N
```

Stops the service, archives the config (does not delete), removes firewall rules and systemd unit.

## Common Management Commands

```bash
# Start/stop all servers
sudo systemctl start cs2-server-{1..4}
sudo systemctl stop cs2-server-{1..4}

# Check status
sudo systemctl status 'cs2-server-*'

# View live logs
journalctl -u cs2-server-1 -f

# Restart a single server
sudo systemctl restart cs2-server-2
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Ensure all scripts pass `shellcheck setup.sh lib/*.sh scripts/*.sh`
4. Test on a fresh Ubuntu 24.04 installation
5. Submit a pull request

## License

[MIT](LICENSE)
