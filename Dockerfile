FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# ----------------------------------------------------
# Native ARM64 dependencies
# ----------------------------------------------------

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    wget \
    git \
    cmake \
    build-essential \
    python3 \
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
    libglib2.0-0 \
    libdbus-1-3 \
    libasound2 \
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
    && rm -rf /var/lib/apt/lists/*


# ----------------------------------------------------
# Box64
# ----------------------------------------------------

RUN git clone --depth=1 \
        https://github.com/ptitSeb/box64.git \
        /tmp/box64 \
    && mkdir -p /tmp/box64/build \
    && cd /tmp/box64/build \
    && cmake .. \
        -DARM_DYNAREC=ON \
        -DCMAKE_BUILD_TYPE=Release \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/box64


# ----------------------------------------------------
# Wine WOW64
# ----------------------------------------------------

ARG WINE_VERSION=11.17

RUN wget \
        "https://github.com/Kron4ek/Wine-Builds/releases/download/${WINE_VERSION}/wine-${WINE_VERSION}-amd64-wow64.tar.xz" \
        -O /tmp/wine.tar.xz \
    && mkdir -p /opt/wine \
    && tar -xJf /tmp/wine.tar.xz \
        --strip-components=1 \
        -C /opt/wine \
    && rm /tmp/wine.tar.xz


# ----------------------------------------------------
# Wine -> Box64 wrappers
# ----------------------------------------------------

RUN cat > /usr/local/bin/wine <<'EOF'
#!/bin/bash
export BOX64_DYNAREC=1
exec /usr/local/bin/box64 /opt/wine/bin/wine "$@"
EOF

RUN cat > /usr/local/bin/wine64 <<'EOF'
#!/bin/bash
export BOX64_DYNAREC=1
wine_binary=/opt/wine/bin/wine64
if [ ! -x "$wine_binary" ]; then
    wine_binary=/opt/wine/bin/wine
fi
exec /usr/local/bin/box64 "$wine_binary" "$@"
EOF

RUN cat > /usr/local/bin/wineserver <<'EOF'
#!/bin/bash
export BOX64_DYNAREC=1
exec /usr/local/bin/box64 /opt/wine/bin/wineserver "$@"
EOF

RUN cat > /usr/local/bin/wineboot <<'EOF'
#!/bin/bash
export BOX64_DYNAREC=1
exec /usr/local/bin/box64 /opt/wine/bin/wineboot "$@"
EOF

RUN cat > /usr/local/bin/winecfg <<'EOF'
#!/bin/bash
export BOX64_DYNAREC=1
exec /usr/local/bin/box64 /opt/wine/bin/winecfg "$@"
EOF

RUN chmod +x \
    /usr/local/bin/wine \
    /usr/local/bin/wine64 \
    /usr/local/bin/wineserver \
    /usr/local/bin/wineboot \
    /usr/local/bin/winecfg


# ----------------------------------------------------
# Persistent directories
# ----------------------------------------------------

RUN mkdir -p \
    /server \
    /data/config \
    /data/wine

ENV WINEPREFIX=/data/wine
ENV WINEARCH=wow64
ENV XDG_CACHE_HOME=/data/cache


# ----------------------------------------------------
# Startup
# ----------------------------------------------------

COPY start.sh /start.sh
COPY bootstrap-wine-services.cmd /opt/bootstrap-wine-services.cmd
COPY install-dependencies.sh /opt/install-dependencies.sh

RUN chmod +x /start.sh /opt/install-dependencies.sh

EXPOSE 27016/udp

ENTRYPOINT ["/start.sh"]
