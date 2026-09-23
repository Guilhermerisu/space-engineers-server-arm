FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

ARG WINE_VERSION=6.0.2
ARG WINE_DEBIAN_VERSION=6.0.2~buster-1

# Wine 6 uses the classic WoW64 layout.  The x86 Wine loader runs through
# Box86 and therefore needs an armhf userspace alongside the native ARM64
# libraries used by Box64.
RUN test "$(dpkg --print-architecture)" = arm64 \
    && dpkg --add-architecture armhf \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        git \
        cmake \
        build-essential \
        gcc-arm-linux-gnueabihf \
        libc6-dev-armhf-cross \
        xz-utils \
        cabextract \
        p7zip-full \
        xvfb \
        xauth \
        fontconfig \
        fonts-dejavu-core \
        fonts-liberation \
        libfontconfig1 \
        libfreetype6 \
        libx11-6 \
        libxext6 \
        libxrender1 \
        libxinerama1 \
        libxcomposite1 \
        libxi6 \
        libxkbregistry0 \
        libxrandr2 \
        libxcursor1 \
        libxfixes3 \
        libxdamage1 \
        libxss1 \
        libxtst6 \
        libxxf86vm1 \
        libglib2.0-0 \
        libdbus-1-3 \
        libasound2 \
        libasound2-plugins \
        libpulse0 \
        libopenal1 \
        libgl1 \
        libegl1 \
        libvulkan1 \
        libgnutls30 \
        libxml2 \
        libkrb5-3 \
        libncurses6 \
        libunwind8 \
        libgphoto2-6 \
        libgphoto2-port12 \
        libusb-1.0-0 \
        libcups2 \
        libodbc2 \
        libpcap0.8 \
        libgsm1 \
        libjpeg62-turbo \
        libpng16-16 \
        liblcms2-2 \
        libldap-2.5-0 \
        libmpg123-0 \
        libfaudio0 \
        libvkd3d1 \
        libfontconfig1:armhf \
        libfreetype6:armhf \
        libx11-6:armhf \
        libxext6:armhf \
        libxrender1:armhf \
        libxinerama1:armhf \
        libxcomposite1:armhf \
        libxi6:armhf \
        libxrandr2:armhf \
        libxcursor1:armhf \
        libxfixes3:armhf \
        libglib2.0-0:armhf \
        libdbus-1-3:armhf \
        libasound2:armhf \
        libasound2-plugins:armhf \
        libpulse0:armhf \
        libopenal1:armhf \
        libgl1:armhf \
        libgnutls30:armhf \
        libxml2:armhf \
        libkrb5-3:armhf \
        libncurses6:armhf \
        libgphoto2-6:armhf \
        libgphoto2-port12:armhf \
        libcups2:armhf \
        libodbc2:armhf \
        libpcap0.8:armhf \
        libgsm1:armhf \
        libjpeg62-turbo:armhf \
        libpng16-16:armhf \
        liblcms2-2:armhf \
        libldap-2.5-0:armhf \
        libmpg123-0:armhf \
        libfaudio0:armhf \
        libvkd3d1:armhf \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*


# ----------------------------------------------------
# Box64 and Box86
# ----------------------------------------------------

COPY box64-lcms.patch /tmp/box64-lcms.patch

RUN git clone --depth=1 \
        https://github.com/ptitSeb/box64.git \
        /tmp/box64 \
    && git -C /tmp/box64 apply /tmp/box64-lcms.patch \
    && cmake -S /tmp/box64 -B /tmp/box64/build \
        -DARM_DYNAREC=ON \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /tmp/box64/build -j"$(nproc)" \
    && cmake --install /tmp/box64/build \
    && rm -rf /tmp/box64 /tmp/box64-lcms.patch

RUN git clone --depth=1 \
        https://github.com/ptitSeb/box86.git \
        /tmp/box86 \
    && cmake -S /tmp/box86 -B /tmp/box86/build \
        -DARM64=1 \
        -DCMAKE_BUILD_TYPE=Release \
    && cmake --build /tmp/box86/build -j"$(nproc)" \
    && cmake --install /tmp/box86/build \
    && rm -rf /tmp/box86


# ----------------------------------------------------
# Wine 6.0.2 classic WoW64
# ----------------------------------------------------

RUN mkdir -p /tmp/wine-packages /tmp/wine-root \
    && wget -q \
        "https://dl.winehq.org/wine-builds/debian/dists/buster/main/binary-i386/wine-stable-i386_${WINE_DEBIAN_VERSION}_i386.deb" \
        -O /tmp/wine-packages/wine-stable-i386.deb \
    && wget -q \
        "https://dl.winehq.org/wine-builds/debian/dists/buster/main/binary-i386/wine-stable_${WINE_DEBIAN_VERSION}_i386.deb" \
        -O /tmp/wine-packages/wine-stable-common-i386.deb \
    && wget -q \
        "https://dl.winehq.org/wine-builds/debian/dists/buster/main/binary-amd64/wine-stable-amd64_${WINE_DEBIAN_VERSION}_amd64.deb" \
        -O /tmp/wine-packages/wine-stable-amd64.deb \
    && wget -q \
        "https://dl.winehq.org/wine-builds/debian/dists/buster/main/binary-amd64/wine-stable_${WINE_DEBIAN_VERSION}_amd64.deb" \
        -O /tmp/wine-packages/wine-stable-common-amd64.deb \
    && echo '4ac2b3d8d662fd37b4f81e9b1e8bc56b18dfc3f0f62af4f9b0f4f276f97289b9  /tmp/wine-packages/wine-stable-i386.deb' | sha256sum -c - \
    && echo 'bc840e8b55a994a925c543d906c61d3b8c1ae820e95d7d943d5486a67001875b  /tmp/wine-packages/wine-stable-common-i386.deb' | sha256sum -c - \
    && echo '27b3f8a48d6fdbfa86f4b5eef9c216c24ccd3fa01c3bfc3df94316c67a53e03b  /tmp/wine-packages/wine-stable-amd64.deb' | sha256sum -c - \
    && echo 'a78fadac387be5de3b9fac0585dde045d9a07ac0214386a1eebb2435bca01540  /tmp/wine-packages/wine-stable-common-amd64.deb' | sha256sum -c - \
    && dpkg-deb -x /tmp/wine-packages/wine-stable-i386.deb /tmp/wine-root \
    && dpkg-deb -x /tmp/wine-packages/wine-stable-common-i386.deb /tmp/wine-root \
    && dpkg-deb -x /tmp/wine-packages/wine-stable-amd64.deb /tmp/wine-root \
    && dpkg-deb -x /tmp/wine-packages/wine-stable-common-amd64.deb /tmp/wine-root \
    && mv /tmp/wine-root/opt/wine-stable /opt/wine \
    && rm -rf /tmp/wine-packages /tmp/wine-root \
    && test -x /opt/wine/bin/wine \
    && test -x /opt/wine/bin/wine64


# ----------------------------------------------------
# Explicit Wine architecture wrappers
# ----------------------------------------------------

RUN cat > /usr/local/bin/wine64 <<'EOF'
#!/bin/bash
export BOX64_DYNAREC=1
exec /usr/local/bin/box64 /opt/wine/bin/wine64 "$@"
EOF

RUN cat > /usr/local/bin/wine32 <<'EOF'
#!/bin/bash
export BOX86_DYNAREC=1
exec /usr/local/bin/box86 /opt/wine/bin/wine "$@"
EOF

RUN cat > /usr/local/bin/wine <<'EOF'
#!/bin/bash
exec /usr/local/bin/wine64 "$@"
EOF

RUN cat > /usr/local/bin/wineserver <<'EOF'
#!/bin/bash
export BOX64_DYNAREC=1
exec /usr/local/bin/box64 /opt/wine/bin/wineserver "$@"
EOF

RUN cat > /usr/local/bin/wineboot <<'EOF'
#!/bin/bash
exec /usr/local/bin/wine64 wineboot.exe "$@"
EOF

RUN cat > /usr/local/bin/winecfg <<'EOF'
#!/bin/bash
exec /usr/local/bin/wine64 winecfg.exe "$@"
EOF

RUN chmod +x \
    /usr/local/bin/wine \
    /usr/local/bin/wine32 \
    /usr/local/bin/wine64 \
    /usr/local/bin/wineserver \
    /usr/local/bin/wineboot \
    /usr/local/bin/winecfg

# Wine 6's MSXML module loads native libxslt in both halves of classic WoW64.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libxslt1.1 \
        libxslt1.1:armhf \
    && rm -rf /var/lib/apt/lists/*


# ----------------------------------------------------
# Persistent directories and startup
# ----------------------------------------------------

RUN mkdir -p /server /data/config /data/wine

ENV WINEPREFIX=/data/wine
ENV WINEARCH=win64
ENV XDG_CACHE_HOME=/data/cache

COPY start.sh /start.sh
COPY bootstrap-wine-services.cmd /opt/bootstrap-wine-services.cmd
COPY install-dependencies.sh /opt/install-dependencies.sh

RUN chmod +x /start.sh /opt/install-dependencies.sh

EXPOSE 27016/udp

ENTRYPOINT ["/start.sh"]
