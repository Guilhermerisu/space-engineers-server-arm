#!/bin/bash
set -euo pipefail

export WINEPREFIX=/data/wine
export WINEARCH=win64
export XDG_CACHE_HOME=/data/cache
export WINESERVER=/usr/local/bin/wineserver

mkdir -p "$WINEPREFIX" /data/config "$XDG_CACHE_HOME"
chown "$(id -u):$(id -g)" "$WINEPREFIX"

echo "======================================"
echo " Space Engineers ARM64 Server"
echo "======================================"

echo
echo "Host architecture:"
uname -m

echo
echo "Box64:"
box64 --version

echo
echo "Box86:"
box86 --version

echo
echo "Wine64:"
wine64 --version

echo
echo "Wine32:"
wine32 --version

echo "======================================"

# --------------------------------------------------
# Initialize the classic Wine 6 WoW64 prefix
# --------------------------------------------------

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo
    echo "Initializing Wine 6 WoW64 prefix..."

    timeout 60s xvfb-run -a \
        -s "-screen 0 1024x768x24" \
        wine64 cmd.exe /c "echo PREFIX_INITIALIZED" || true

    timeout 15s wineserver -k || true
    test -f "$WINEPREFIX/system.reg"
fi

wine_version="$(wine64 --version)"
system_files_marker="$WINEPREFIX/.classic-wow64-files-v1-$wine_version"

if [ ! -f "$system_files_marker" ]; then
    echo
    echo "Installing Wine 6 32-bit system files..."

    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
    find /opt/wine/lib/wine -maxdepth 1 -type f \
        ! -name '*.so' ! -name '*.def' ! -name '*.a' \
        -exec cp -a '{}' "$WINEPREFIX/drive_c/windows/syswow64/" ';'

    test -f "$WINEPREFIX/drive_c/windows/syswow64/cmd.exe"
    touch "$system_files_marker"
fi

services_marker="$WINEPREFIX/.core-services-v5-$wine_version"

if [ ! -f "$services_marker" ]; then
    echo
    echo "Registering Wine core services..."

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
    echo
    echo "Validating Wine 6 64-bit and 32-bit subsystems..."

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
    echo
    echo "Registering Wine core components..."

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

dependencies_marker="/data/.dependencies-installed-$wine_version"

if [ ! -f "$dependencies_marker" ]; then
    echo
    echo "Installing .NET 4.8 and Visual C++ runtimes..."

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
    echo
    echo "Disabling .NET NGen services..."

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

if [ ! -f /server/DedicatedServer64/SpaceEngineersDedicated.exe ]; then
    echo
    echo "======================================"
    echo "SPACE ENGINEERS NOT INSTALLED"
    echo "======================================"
    echo
    echo "Run:"
    echo
    echo "    docker compose run --rm downloader"
    echo
    exit 1
fi

echo
echo "Space Engineers installation found."

if [ ! -f /data/config/SpaceEngineers-Dedicated.cfg ]; then
    echo
    echo "======================================"
    echo "CONFIGURATION NOT FOUND"
    echo "======================================"
    echo
    echo "Expected:"
    echo
    echo "    /data/config/SpaceEngineers-Dedicated.cfg"
    echo "    /data/config/Saves/..."
    echo
    echo "Copy your server configuration into:"
    echo
    echo "    /opt/space-engineers/data/config/"
    echo
    exit 1
fi

# --------------------------------------------------
# Start Space Engineers
# --------------------------------------------------

echo
echo "Starting Space Engineers Dedicated Server..."
echo

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
    echo "Xvfb did not become ready." >&2
    exit 1
fi

export DISPLAY=:99
export WINEDEBUG=-all
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

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching SpaceEngineersDedicated.exe"

latest_game_log() {
    find /data/config -maxdepth 1 -type f \
        -name 'SpaceEngineersDedicated_*.log' -printf '%f\n' \
        | LC_ALL=C sort | tail -n 1
}

previous_game_log="$(latest_game_log)"

wine64 SpaceEngineersDedicated.exe \
    -console \
    -steam \
    -path 'Z:\data\config' &
game_pid=$!

# Forward the log created by this launch to Docker's stdout. Every container
# restart gets a fresh follower, so old game logs are never replayed.
(
    while :; do
        current_game_log="$(latest_game_log)"
        if [ -n "$current_game_log" ] && [ "$current_game_log" != "$previous_game_log" ]; then
            echo "Following game log: $current_game_log"
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

echo "[$(date '+%Y-%m-%d %H:%M:%S')] SpaceEngineersDedicated.exe (wine64) exited with status $game_status"
exit "$game_status"
