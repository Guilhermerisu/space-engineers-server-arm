#!/bin/bash
set -e

export WINEPREFIX=/data/wine
export WINEARCH=wow64
export XDG_CACHE_HOME=/data/cache

mkdir -p "$WINEPREFIX"
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
echo "Wine:"
wine --version

echo
echo "======================================"

mkdir -p /data/config
mkdir -p "$XDG_CACHE_HOME"

# --------------------------------------------------
# Initialize Wine prefix
# --------------------------------------------------

if [ ! -f "$WINEPREFIX/system.reg" ]; then
    echo
    echo "Initializing Wine prefix..."

    timeout 60s xvfb-run -a \
        -s "-screen 0 1024x768x24" \
        wine cmd.exe /c "echo PREFIX_INITIALIZED" || true

    timeout 10s wineserver -k || true
fi

# Wine's unified WoW64 prefix initialization can stop before it copies the
# bundled 32-bit Windows files when running through Box64. The x64 server still
# needs these files because the .NET and VC++ installers have 32-bit launchers.
wine_version="$(wine --version)"
wow64_marker="$WINEPREFIX/.system-files-$wine_version"

if [ ! -f "$wow64_marker" ]; then
    echo
    echo "Installing Wine WoW64 system files for $wine_version..."

    mkdir -p "$WINEPREFIX/drive_c/windows/syswow64"
    cp -a /opt/wine/lib/wine/i386-windows/. \
        "$WINEPREFIX/drive_c/windows/syswow64/"

    if ! timeout 30s xvfb-run -a \
        -s "-screen 0 1024x768x24" \
        wine 'C:\windows\syswow64\cmd.exe' \
            /c "echo WOW64_INITIALIZED"; then
        echo "Failed to initialize Wine's 32-bit subsystem." >&2
        exit 1
    fi

    timeout 10s wineserver -k || true
    touch "$wow64_marker"
fi

services_marker="$WINEPREFIX/.core-services-v4-$wine_version"

if [ ! -f "$services_marker" ]; then
    echo
    echo "Registering Wine core services..."

    xvfb-run -a \
        -s "-screen 0 1024x768x24" \
        wine cmd.exe /c 'Z:\opt\bootstrap-wine-services.cmd'

    timeout 10s wineserver -k || true

    xvfb-run -a \
        -s "-screen 0 1024x768x24" \
        wine sc.exe query MountMgr >/dev/null

    timeout 10s wineserver -k || true
    touch "$services_marker"
fi

components_marker="$WINEPREFIX/.core-components-v1-$wine_version"

if [ ! -f "$components_marker" ]; then
    echo
    echo "Registering Wine core components..."

    xvfb-run -a \
        -s "-screen 0 1024x768x24" \
        wine regsvr32.exe /s msxml3.dll || true
    timeout 10s wineserver -k || true

    # The 32-bit registrar currently crashes while shutting down under Box64,
    # after it has successfully written the registration.
    xvfb-run -a \
        -s "-screen 0 1024x768x24" \
        wine 'C:\windows\syswow64\regsvr32.exe' \
            /s 'C:\windows\syswow64\msxml3.dll' || true
    timeout 10s wineserver -k || true

    xvfb-run -a \
        -s "-screen 0 1024x768x24" \
        wine 'C:\windows\syswow64\reg.exe' query \
            'HKCR\CLSID\{F5078F32-C551-11D3-89B9-0000F81FE221}' \
            >/dev/null

    timeout 10s wineserver -k || true
    touch "$components_marker"
fi

# --------------------------------------------------
# Install Windows dependencies once
# --------------------------------------------------

if [ ! -f /data/.dependencies-installed ]; then
    echo
    echo "Installing .NET 4.8 and Visual C++ runtimes..."

    /opt/install-dependencies.sh

    touch /data/.dependencies-installed
fi

# --------------------------------------------------
# Check Space Engineers installation
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

# --------------------------------------------------
# Check configuration
# --------------------------------------------------

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
    echo "    /opt/space-engineers-arm/data/config/"
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

# xvfb-run has a startup signal race under this ARM container: Xvfb can become
# ready before its parent begins waiting, leaving the wrapper asleep forever.
# Start and supervise the display directly so the game launch is deterministic.
Xvfb :99 -screen 0 1024x768x24 -nolisten tcp \
    >/tmp/space-engineers-xvfb.log 2>&1 &
xvfb_pid=$!
game_pid=

stop_wine() {
    timeout 15s wineserver -k || true
}

cleanup() {
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
# Use conservative Box64 settings for the CLR and Havok workloads.
export BOX64_PROFILE=safest
export BOX64_DYNAREC_INTERP_SIGNAL=1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Launching SpaceEngineersDedicated.exe"

wine SpaceEngineersDedicated.exe \
    -console \
    -steam \
    -path 'Z:\data\config' &
game_pid=$!

game_status=0
wait "$game_pid" || game_status=$?

echo "[$(date '+%Y-%m-%d %H:%M:%S')] SpaceEngineersDedicated.exe (wine) exited with status $game_status"
exit "$game_status"
