#!/bin/bash
set -euo pipefail

export WINEDEBUG=-all

download_checked() {
    local url="$1"
    local sha256="$2"
    local destination="$3"

    mkdir -p "$(dirname "$destination")"
    if [ ! -f "$destination" ]; then
        wget -q "$url" -O "$destination.tmp"
        mv "$destination.tmp" "$destination"
    fi

    echo "$sha256  $destination" | sha256sum -c -
}

Xvfb :98 -screen 0 1024x768x24 -nolisten tcp \
    >/tmp/dependency-xvfb.log 2>&1 &
xvfb_pid=$!
trap 'kill "$xvfb_pid" 2>/dev/null || true' EXIT
export DISPLAY=:98

sleep 1

dotnet40_package="$XDG_CACHE_HOME/dependencies/dotnet40/dotNetFx40_Full_x86_x64.exe"
download_checked \
    'https://download.microsoft.com/download/9/5/A/95A9616B-7A37-4AF6-BC36-D6EA96C8DAAE/dotNetFx40_Full_x86_x64.exe' \
    '65e064258f2e418816b304f646ff9e87af101e4c9552ab064bb74d281c38659f' \
    "$dotnet40_package"

framework32="$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319"
framework64="$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319"

if [ ! -f "$framework32/ngen.exe" ] || [ ! -f "$framework64/ngen.exe" ]; then
    echo "Installing the .NET 4 base runtime from verified MSI payloads..."

    rm -rf "$WINEPREFIX/drive_c/dotnet40"
    mkdir -p "$WINEPREFIX/drive_c/dotnet40"
    7z x -y -o"$WINEPREFIX/drive_c/dotnet40" \
        "$dotnet40_package" >/dev/null

    timeout 60s winecfg -v winxp64
    wine msiexec.exe \
        /i 'C:\dotnet40\RGB9RAST_x64.msi' \
        /qn EXTUI=1 \
        '/l*v' 'C:\dotnet40\rgb-x64.log'
    wine msiexec.exe \
        /i 'C:\dotnet40\netfx_Core_x64.msi' \
        /qn EXTUI=1 \
        '/l*v' 'C:\dotnet40\core-x64.log'

    test -f "$framework32/ngen.exe"
    test -f "$framework64/ngen.exe"
    rm -rf "$WINEPREFIX/drive_c/dotnet40"
fi

dotnet48_package="$XDG_CACHE_HOME/dependencies/dotnet48/ndp48-x86-x64-allos-enu.exe"
download_checked \
    'https://download.visualstudio.microsoft.com/download/pr/7afca223-55d2-470a-8edc-6a1739ae3252/abd170b4b0ec15ad0222a809b761a036/ndp48-x86-x64-allos-enu.exe' \
    '95889d6de3f2070c07790ad6cf2000d33d9a1bdfc6a381725ab82ab1c314fd53' \
    "$dotnet48_package"

if ! wine reg.exe query \
    'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' \
    /v Release 2>/dev/null | grep -qi '0x80eb1'; then
    echo "Installing .NET 4.8 from its verified MSI payload..."

    rm -rf "$WINEPREFIX/drive_c/dotnet48"
    mkdir -p "$WINEPREFIX/drive_c/dotnet48"
    7z x -y -o"$WINEPREFIX/drive_c/dotnet48" \
        "$dotnet48_package" >/dev/null

    timeout 60s winecfg -v win7
    wine msiexec.exe \
        /i 'C:\dotnet48\netfx_Full_x64.msi' \
        /qn EXTUI=1 \
        '/l*v' 'C:\dotnet48\full-x64.log'

    wine reg.exe query \
        'HKLM\Software\Microsoft\NET Framework Setup\NDP\v4\Full' \
        /v Release | grep -qi '0x80eb1'
    wine reg.exe query \
        'HKLM\Software\Wow6432Node\Microsoft\NET Framework Setup\NDP\v4\Full' \
        /v Release | grep -qi '0x80eb1'

    touch "$WINEPREFIX/drive_c/windows/dotnet48.installed.workaround"
    rm -rf "$WINEPREFIX/drive_c/dotnet48"
fi

# Previous interrupted installer attempts may have left their expanded payloads
# behind even when the runtime itself was installed successfully.
rm -rf \
    "$WINEPREFIX/drive_c/dotnet40" \
    "$WINEPREFIX/drive_c/dotnet48"

vc2013_cache="$XDG_CACHE_HOME/dependencies/vcrun2013"
download_checked \
    'https://download.microsoft.com/download/0/5/6/056dcda9-d667-4e27-8001-8a0c6971d6b1/vcredist_x86.exe' \
    '89f4e593ea5541d1c53f983923124f9fd061a1c0c967339109e375c661573c17' \
    "$vc2013_cache/vcredist_x86.exe"
download_checked \
    'https://download.microsoft.com/download/0/5/6/056dcda9-d667-4e27-8001-8a0c6971d6b1/vcredist_x64.exe' \
    '20e2645b7cd5873b1fa3462b99a665ac8d6e14aae83ded9d875fea35ffdd7d7e' \
    "$vc2013_cache/vcredist_x64.exe"

vc2017_cache="$XDG_CACHE_HOME/dependencies/vcrun2017"
download_checked \
    'https://aka.ms/vs/15/release/vc_redist.x86.exe' \
    '251640e8039d34290133b2c6e3e6fe098e61e2756d5a4c45fdcec9e4dee6c187' \
    "$vc2017_cache/vc_redist.x86.exe"
download_checked \
    'https://aka.ms/vs/15/release/vc_redist.x64.exe' \
    '7cf24eba2bd67ea6229b7dd131e06f4e92ebefc06e36fe401cdd227d7ed78264' \
    "$vc2017_cache/vc_redist.x64.exe"

echo "Installing Visual C++ runtime DLLs from verified CAB payloads..."

rm -rf /tmp/vc-runtime
mkdir -p /tmp/vc-runtime

for arch in x86 x64; do
    work="/tmp/vc-runtime/vc2013-$arch"
    mkdir -p "$work/outer" "$work/dlls"
    cabextract -q -d "$work/outer" "$vc2013_cache/vcredist_$arch.exe"
    cabextract -q -d "$work/dlls" "$work/outer/a2"
    cabextract -q -d "$work/dlls" "$work/outer/a3"

    if [ "$arch" = x86 ]; then
        destination="$WINEPREFIX/drive_c/windows/syswow64"
    else
        destination="$WINEPREFIX/drive_c/windows/system32"
    fi

    for source in "$work/dlls"/F_CENTRAL_*_"$arch"; do
        filename="${source##*/F_CENTRAL_}"
        filename="${filename%_"$arch"}.dll"
        install -m 0644 "$source" "$destination/$filename"
    done
done

for arch in x86 x64; do
    work="/tmp/vc-runtime/vc2017-$arch"
    mkdir -p "$work/outer" "$work/runtime" "$work/mfc"
    cabextract -q -d "$work/outer" "$vc2017_cache/vc_redist.$arch.exe"
    cabextract -q -d "$work/runtime" "$work/outer/a10"
    cabextract -q -d "$work/mfc" "$work/outer/a11"

    if [ "$arch" = x86 ]; then
        destination="$WINEPREFIX/drive_c/windows/syswow64"
    else
        destination="$WINEPREFIX/drive_c/windows/system32"
    fi

    for filename in \
        concrt140.dll \
        msvcp140.dll \
        msvcp140_1.dll \
        msvcp140_2.dll \
        ucrtbase.dll \
        vcamp140.dll \
        vccorlib140.dll \
        vcomp140.dll \
        vcruntime140.dll; do
        install -m 0644 "$work/runtime/$filename" "$destination/$filename"
    done

    for source in "$work/mfc"/*.dll; do
        install -m 0644 "$source" "$destination/${source##*/}"
    done
done

for dll in \
    msvcp120 msvcr120 vcomp120 mfc120 mfc120u mfcm120 mfcm120u \
    concrt140 msvcp140 msvcp140_1 msvcp140_2 ucrtbase vcamp140 \
    vccorlib140 vcomp140 vcruntime140 mfc140 mfc140u mfcm140 mfcm140u; do
    wine reg.exe add 'HKCU\Software\Wine\DllOverrides' \
        /v "$dll" /t REG_SZ /d native,builtin /f >/dev/null
done

# The dedicated server checks these MSI provider keys in addition to loading
# the runtime DLLs. Wine's Burn host cannot run the redistributable wrapper, so
# register the metadata from the two verified x64 MSI payloads explicitly.
vc_minimum_key='HKLM\Software\Classes\Installer\Dependencies\Microsoft.VS.VC_RuntimeMinimumVSU_amd64,v14'
vc_additional_key='HKLM\Software\Classes\Installer\Dependencies\Microsoft.VS.VC_RuntimeAdditionalVSU_amd64,v14'

wine reg.exe add "$vc_minimum_key" /ve /t REG_SZ \
    /d '{9A4F7AD7-1B9D-4432-9F31-AB6602ADB4F5}' /f >/dev/null
wine reg.exe add "$vc_minimum_key" /v DisplayName /t REG_SZ \
    /d 'Microsoft Visual C++ 2017 X64 Minimum Runtime - 14.16.27052' \
    /f >/dev/null
wine reg.exe add "$vc_minimum_key" /v Version /t REG_SZ \
    /d '14.16.27052' /f >/dev/null

wine reg.exe add "$vc_additional_key" /ve /t REG_SZ \
    /d '{1A673510-C931-4258-BDE7-41C5D306747E}' /f >/dev/null
wine reg.exe add "$vc_additional_key" /v DisplayName /t REG_SZ \
    /d 'Microsoft Visual C++ 2017 X64 Additional Runtime - 14.16.27052' \
    /f >/dev/null
wine reg.exe add "$vc_additional_key" /v Version /t REG_SZ \
    /d '14.16.27052' /f >/dev/null

wine reg.exe query "$vc_minimum_key" >/dev/null
wine reg.exe query "$vc_additional_key" >/dev/null

test -f "$WINEPREFIX/drive_c/windows/system32/msvcr120.dll"
test -f "$WINEPREFIX/drive_c/windows/syswow64/msvcr120.dll"
test -f "$WINEPREFIX/drive_c/windows/system32/vcruntime140.dll"
test -f "$WINEPREFIX/drive_c/windows/syswow64/vcruntime140.dll"

timeout 60s winecfg -v win10
timeout 15s wineserver -k || true
