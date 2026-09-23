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
<LoadWorld>Z:\data\config\Saves\YourWorld</LoadWorld>
```

Keep the Remote API disabled because its Windows HTTP listener does not work
correctly under Wine.

## 5. Apply the server-GC compatibility setting

Inside the `<runtime>` element of
`server/DedicatedServer64/SpaceEngineersDedicated.exe.config`, add:

```xml
<gcServer enabled="true" />
```

Check this again after updating the dedicated server because validation may
overwrite the file.

## 6. Open the firewall ports

Allow UDP ports `27016` and `8766` in both the host firewall and the cloud
provider firewall. For UFW:

```bash
sudo ufw allow 27016/udp
sudo ufw allow 8766/udp
```

The container uses host networking, so Docker port mappings are not needed.

## 7. Build and start

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
Game ready... Press Ctrl+C to exit
```

Connect using the server's public IP and port `27016`.

The first launch also installs .NET 4.8 and Visual C++ runtimes into the
persistent Wine prefix, so it takes longer than later starts.

## 8. Manage the server

```bash
# Status
docker compose ps

# Restart
docker compose restart space-engineers

# Stop gracefully
docker compose stop space-engineers

# Recent output
docker compose logs --tail 200 space-engineers
```

## 9. Update

```bash
docker compose stop space-engineers
docker compose run --rm downloader
docker compose build space-engineers
docker compose up -d --force-recreate space-engineers
```

After downloading an update, repeat step 5 before starting the server.

## 10. Startup reliability

This ARM64 emulation setup has shown intermittent startup crashes. Reaching `Game ready`
confirms that a launch completed; let it retry some times and continue monitoring the game log for runtime
failures. Docker's `unless-stopped` policy restarts the container after exits.
