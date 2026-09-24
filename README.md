# Space Engineers Dedicated Server on ARM64 with Wine 6.0.2

Run the Windows Space Engineers Dedicated Server on ARM64 Linux with Docker

## 1. Requirements

- ARM64 Linux server
- Docker Engine and the Docker Compose plugin
- At least 20 GB of free disk space
- A Space Engineers world save and `SpaceEngineers-Dedicated.cfg`

## 2. Clone the project

```bash
git clone https://github.com/Guilhermerisu/space-engineers-server-arm.git
cd space-engineers-server-arm
```

## 3. Download the dedicated server

```bash
docker compose run --rm downloader
```

## 4. Add the configuration and world

Create this directory structure:

```text
data/config/
├── SpaceEngineers-Dedicated.cfg
└── Saves/
```

Set these values in `data/config/SpaceEngineers-Dedicated.cfg`:

```xml
<IP>0.0.0.0</IP>
<SteamPort>8766</SteamPort>
<ServerPort>27016</ServerPort>
<NetworkType>steam</NetworkType>
<RemoteApiEnabled>false</RemoteApiEnabled>
<AutodetectDependencies>false</AutodetectDependencies>
<LoadWorld>Z:\data\config\Saves\YourWorld</LoadWorld>
```

Keep the Remote API disabled because its Windows HTTP listener does not work
correctly under Wine. With `AutodetectDependencies` off, the server skips one
Workshop query at startup; list every dependency mod in the world instead.

## 5. Apply the server-GC compatibility setting

Inside the `<runtime>` element of
`server/DedicatedServer64/SpaceEngineersDedicated.exe.config`, add:

```xml
<gcServer enabled="true" />
```

## 6. Update the Steam client libraries

```bash
docker compose run --rm downloader -app 1007 -os windows -osarch 64 -dir /server/steamworks-redist
for f in steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do
    sudo cp server/steamworks-redist/$f server/DedicatedServer64/$f
done
```

## 7. Open the firewall ports

Allow UDP ports `27016` and `8766` in both the host firewall and the cloud
provider firewall. For UFW:

```bash
sudo ufw allow 27016/udp
sudo ufw allow 8766/udp
```

Docker publishes these ports (see `ports` in `docker-compose.yml`). To use
other ports, change them in both `docker-compose.yml` and
`SpaceEngineers-Dedicated.cfg`.

## 8. Build and start

```bash
docker compose build space-engineers
docker compose up -d --force-recreate space-engineers
```

Watch startup:

```bash
docker compose logs -f space-engineers
```

```text
Server connected to Steam
Mod query successful
Mod download successful.          (once per mod, first start only)
Game ready... Press Ctrl+C to exit
```

Connect using the server's public IP and port `27016`.

The first launch also installs .NET 4.8 and Visual C++ runtimes into the
persistent Wine prefix, so it takes longer than later starts.

## 9. Manage the server

```bash
# Status
docker compose ps

# Restart
docker compose restart space-engineers

# Stop gracefully
docker compose stop space-engineers

# Recent output
docker compose logs --tail 200 space-engineers

# Wine output of the current launch
tail -f "$(ls -t data/logs/wine-*.log | head -1)"
```
