#!/bin/bash
set -euo pipefail

export WINEPREFIX=/data/wine
export WINEARCH=win64
export XDG_CACHE_HOME=/data/cache
export WINESERVER=/usr/local/bin/wineserver

# Wine's own output, including the debug trace, goes to a file per launch so
# the container log shows only these startup steps and the game log.
WINE_LOG_DIR=/data/logs
WINE_LOG_KEEP="${SE_WINE_LOG_KEEP:-5}"

log_step() {
    printf '\n[%s] [STEP] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

log_info() {
    printf '[%s] [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

log_error() {
    printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

mkdir -p "$WINEPREFIX" /data/config "$XDG_CACHE_HOME" "$WINE_LOG_DIR"
chown "$(id -u):$(id -g)" "$WINEPREFIX"

log_step "1/6 Check host and compatibility layers"
log_info "$(uname -m) | $(box64 --version 2>&1 | tail -n 1 | cut -d' ' -f1-3) | $(wine64 --version)"

log_step "2/6 Prepare Wine prefix"

# --------------------------------------------------
# Initialize the classic Wine 6 WoW64 prefix
# --------------------------------------------------

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    log_info "Initializing Wine 6 WoW64 prefix"

    timeout 60s xvfb-run -a \
        -s "-screen 0 1024x768x24" \
        wine64 cmd.exe /c "echo PREFIX_INITIALIZED" || true

    timeout 15s wineserver -k || true
    test -f "$WINEPREFIX/system.reg"
fi

wine_version="$(wine64 --version)"
system_files_marker="$WINEPREFIX/.classic-wow64-files-v1-$wine_version"

if [ ! -f "$system_files_marker" ]; then
    log_info "Installing Wine 6 32-bit system files"

    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
    find /opt/wine/lib/wine -maxdepth 1 -type f \
        ! -name '*.so' ! -name '*.def' ! -name '*.a' \
        -exec cp -a '{}' "$WINEPREFIX/drive_c/windows/syswow64/" ';'

    test -f "$WINEPREFIX/drive_c/windows/syswow64/cmd.exe"
    touch "$system_files_marker"
fi

services_marker="$WINEPREFIX/.core-services-v5-$wine_version"

if [ ! -f "$services_marker" ]; then
    log_info "Registering Wine core services"

    xvfb-run -a -s "-screen 0 1024x768x24" \
        wine64 cmd.exe /c 'Z:\opt\bootstrap-wine-services.cmd'
    timeout 15s wineserver -k || true

    xvfb-run -a -s "-screen 0 1024x768x24" \
        wine64 reg.exe query \
            'HKLM\System\CurrentControlSet\Services\MountMgr' \
            >/dev/null
    timeout 15s wineserver -k || true

    touch "$services_marker"
fi

wow64_marker="$WINEPREFIX/.classic-wow64-v2-$wine_version"

if [ ! -f "$wow64_marker" ]; then
    log_info "Validating Wine 6 64-bit and 32-bit subsystems"

    xvfb-run -a -s "-screen 0 1024x768x24" \
        wine64 cmd.exe /c "echo WINE64_INITIALIZED"
    timeout 15s wineserver -k || true

    xvfb-run -a -s "-screen 0 1024x768x24" \
        wine32 cmd.exe /c "echo WINE32_INITIALIZED"
    timeout 15s wineserver -k || true

    touch "$wow64_marker"
fi

components_marker="$WINEPREFIX/.core-components-v3-$wine_version"

if [ ! -f "$components_marker" ]; then
    log_info "Registering Wine core components"

    xvfb-run -a -s "-screen 0 1024x768x24" \
        wine64 regsvr32.exe /s msxml3.dll || true
    timeout 15s wineserver -k || true

    xvfb-run -a -s "-screen 0 1024x768x24" \
        wine32 regsvr32.exe /s msxml3.dll || true
    timeout 15s wineserver -k || true

    xvfb-run -a -s "-screen 0 1024x768x24" \
        wine32 reg.exe query \
            'HKCR\CLSID\{F5078F32-C551-11D3-89B9-0000F81FE221}' \
            >/dev/null
    timeout 15s wineserver -k || true

    touch "$components_marker"
fi

# --------------------------------------------------
# Install Windows dependencies once
# --------------------------------------------------

log_step "3/6 Prepare Windows dependencies"

dependencies_marker="/data/.dependencies-installed-$wine_version"

if [ ! -f "$dependencies_marker" ]; then
    log_info "Installing .NET 4.8 and Visual C++ runtimes"

    /opt/install-dependencies.sh

    touch "$dependencies_marker"
fi

# --------------------------------------------------
# Disable background NGen
# --------------------------------------------------

# The .NET optimization services recompile framework assemblies into native
# images under Box64 while the server loads.  Native images produced that way
# are unreliable, so keep the services disabled and let the CLR JIT instead.
ngen_marker="$WINEPREFIX/.ngen-disabled-v1"

if [ ! -f "$ngen_marker" ]; then
    log_info "Disabling .NET NGen services"

    for service in clr_optimization_v4.0.30319_32 clr_optimization_v4.0.30319_64; do
        wine64 reg.exe add \
            "HKLM\\System\\CurrentControlSet\\Services\\$service" \
            /v Start /t REG_DWORD /d 4 /f >/dev/null
    done
    timeout 15s wineserver -k || true

    touch "$ngen_marker"
fi

# --------------------------------------------------
# Check Space Engineers installation and config
# --------------------------------------------------

log_step "4/6 Validate server files and configuration"

if [ ! -f /server/DedicatedServer64/SpaceEngineersDedicated.exe ]; then
    log_error "Space Engineers is not installed. Run:"
    log_error "    docker compose run --rm downloader"
    exit 1
fi

if [ ! -f /data/config/SpaceEngineers-Dedicated.cfg ]; then
    log_error "Configuration not found. Expected:"
    log_error "    /data/config/SpaceEngineers-Dedicated.cfg"
    log_error "    /data/config/Saves/..."
    log_error "Copy your server configuration into /opt/space-engineers/data/config/"
    exit 1
fi

# --------------------------------------------------
# Start Space Engineers
# --------------------------------------------------

log_step "5/6 Start virtual display"

cd /server/DedicatedServer64

Xvfb :99 -screen 0 1024x768x24 -nolisten tcp \
    >/tmp/space-engineers-xvfb.log 2>&1 &
xvfb_pid=$!
game_pid=
game_log_pid=

stop_wine() {
    timeout 15s wineserver -k || true
}

stop_game_log() {
    if [ -n "$game_log_pid" ]; then
        kill "$game_log_pid" 2>/dev/null || true
        wait "$game_log_pid" 2>/dev/null || true
        game_log_pid=
    fi
}

cleanup() {
    stop_game_log
    stop_wine
    kill "$xvfb_pid" 2>/dev/null || true
    wait "$xvfb_pid" 2>/dev/null || true
}

trap stop_wine TERM INT
trap cleanup EXIT

for _ in $(seq 1 50); do
    if [ -S /tmp/.X11-unix/X99 ]; then
        break
    fi
    if ! kill -0 "$xvfb_pid" 2>/dev/null; then
        cat /tmp/space-engineers-xvfb.log >&2
        exit 1
    fi
    sleep 0.1
done

if [ ! -S /tmp/.X11-unix/X99 ]; then
    log_error "Xvfb did not become ready"
    exit 1
fi

log_step "6/6 Launch Space Engineers"

export DISPLAY=:99
# Wine 6 loses the server's Steam connection right after the Workshop mod
# query when tracing is off; with socket tracing on, the connection has held.
export WINEDEBUG=+timestamp,+tid,+winsock,+iphlpapi,warn+all,err+all
export BOX64_PROFILE=safest
export BOX64_DYNAREC_INTERP_SIGNAL=1
# The server's parallel entity loader races under the weaker ARM memory model
# and fails with AccessViolationException; emulate x86 ordering more strictly.
export BOX64_DYNAREC_STRONGMEM=3
export BOX64_DYNAREC_WEAKBARRIER=0
# Ignore NGen native images so framework code is JIT-compiled at runtime.
export COMPlus_ZapDisable=1
# libdbus aborts the process on API misuse checks by default; Wine hits one
# when no system bus exists in the container.
export DBUS_FATAL_WARNINGS=0

latest_game_log() {
    find /data/config -maxdepth 1 -type f \
        -name 'SpaceEngineersDedicated_*.log' -printf '%f\n' \
        | LC_ALL=C sort | tail -n 1
}

previous_game_log="$(latest_game_log)"

# Keep only the newest Wine logs; each traced launch writes tens of megabytes.
find "$WINE_LOG_DIR" -maxdepth 1 -type f -name 'wine-*.log' -printf '%f\n' \
    | LC_ALL=C sort | head -n "-$((WINE_LOG_KEEP - 1))" \
    | while read -r old_log; do rm -f "$WINE_LOG_DIR/$old_log"; done
wine_log="$WINE_LOG_DIR/wine-$(date '+%Y%m%d-%H%M%S').log"

log_info "Launching SpaceEngineersDedicated.exe (Wine output: data/${wine_log#/data/})"

wine64 SpaceEngineersDedicated.exe \
    -console \
    -steam \
    -path 'Z:\data\config' \
    >"$wine_log" 2>&1 &
game_pid=$!

# Forward the log created by this launch to Docker's stdout. Every container
# restart gets a fresh follower, so old game logs are never replayed.
(
    while :; do
        current_game_log="$(latest_game_log)"
        if [ -n "$current_game_log" ] && [ "$current_game_log" != "$previous_game_log" ]; then
            exec tail -n +1 -F "/data/config/$current_game_log"
        fi
        sleep 1
    done
) &
game_log_pid=$!

game_status=0
wait "$game_pid" || game_status=$?

# Allow tail to consume the final crash or shutdown lines before exiting.
sleep 2
stop_game_log

log_info "SpaceEngineersDedicated.exe (wine64) exited with status $game_status"
exit "$game_status"
