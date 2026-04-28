[Unit]
Description=CS2 Dedicated Server - Instance %%INSTANCE_NUM%%
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=%%SERVICE_USER%%
Group=%%SERVICE_USER%%
WorkingDirectory=%%INSTALL_DIR%%/serverfiles

EnvironmentFile=%%INSTALL_DIR%%/instances/server-%%INSTANCE_NUM%%/instance.env

# Verify Metamod gameinfo.gi patch before starting
ExecStartPre=/bin/bash -c '\
    GI="%%INSTALL_DIR%%/serverfiles/game/csgo/gameinfo.gi"; \
    if [ -f "$GI" ] && ! grep -q "csgo/addons/metamod" "$GI"; then \
        sed -i "/Game_LowViolence/a\\\\t\\t\\tGame\\tcsgo/addons/metamod" "$GI"; \
    fi'

ExecStart=%%INSTALL_DIR%%/serverfiles/game/bin/linuxsteamrt64/cs2 \
    -dedicated \
    -console \
    -usercon \
    -port %%GAME_PORT%% \
    +clientport %%CLIENT_PORT%% \
    +tv_port %%GOTV_PORT%% \
    +game_type 0 \
    +game_mode 1 \
    +mapgroup mg_active \
    +map de_dust2 \
    +servercfgfile server-%%INSTANCE_NUM%%/server.cfg \
    -maxplayers %%MAX_PLAYERS%% \
    -ip 0.0.0.0

Restart=on-failure
RestartSec=15
LimitNOFILE=100000

StandardOutput=append:%%INSTALL_DIR%%/logs/server-%%INSTANCE_NUM%%/console.log
StandardError=append:%%INSTALL_DIR%%/logs/server-%%INSTANCE_NUM%%/error.log

[Install]
WantedBy=multi-user.target
