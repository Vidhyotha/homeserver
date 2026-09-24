# My Nitro 5 HomeServer

A pure-Docker infrastructure running on an Acer Nitro 5 (**192.168.1.32**). This repository serves as a backup for configurations and a technical guide for the stack.

## Network Architecture

The network follows a three-step handshake to enable clean `.home` URLs house-wide:

1. **ZTE Router:** DHCP Primary DNS set to `192.168.1.32` and **ISP DNS** toggled **Off**.
2. **AdGuard Home:** Acts as the DNS resolver, rewriting `.home` domains to the server IP.
3. **Nginx Proxy Manager (NPM):** Acts as the reverse proxy, routing traffic from Port 80 to specific service ports.

### VPN & Remote Access
- **Tailscale**: Deployed in `network_mode: host` to act as a Subnet Router (advertising `192.168.1.0/24`).
- **Global DNS**: Tailscale is configured to override local DNS and point all remote devices to the AdGuard Home container to seamlessly resolve `.home` local domains on the go.
- **Reproduced in Compose**: The otherwise-manual `tailscale up` flags are now encoded as `TS_ACCEPT_DNS=false` and `TS_EXTRA_ARGS=--advertise-routes=192.168.1.0/24`, so re-deploying restores the subnet router automatically. If the node reports `Logged out`, re-authenticate once:
  ```bash
  docker exec tailscale tailscale up --accept-dns=false --advertise-routes=192.168.1.0/24
  ```
  then approve the printed URL in the Tailscale admin console.

## Services & Local URLs

| Service | Host Port | Local URL | Description |
| --- | --- | --- | --- |
| **NPM** | 81 | `http://192.168.1.32:81` | Reverse Proxy Management |
| **AdGuard** | 8081 | `http://192.168.1.32:8081` | Network-wide DNS & Ad-blocking |
| **Homepage** | 3001 | `http://dashboard.home` | Central Service Dashboard |
| **Arcane** | 3552 | `http://arcane.home` | Personal Docker Environment Manager |
| **Open-WebUI** | 3000 | `http://ai.home` | AI Chat Interface (Websockets enabled) |
| **Navidrome** | 4533 | `http://music.home` | Personal Music Server |
| **Stremio** | 8080 | `http://stremio.home` | Universal Media Aggregator |
| **Watchtower** | 9393 | `http://192.168.1.32:9393` | Automated Container Updates (API) |

## Technical Implementation & Fixes

### 1. The Apple `.local` mDNS Conflict (iPad/macOS Fix)

Initially used `.local` domains, but Apple devices failed to resolve them because iOS/macOS strictly reserves `.local` for its internal Bonjour/mDNS service.

* **Fix:** Migrated all DNS rewrites in AdGuard and Proxy Hosts in NPM to use the `.home` TLD (e.g., `dashboard.home`) to bypass Apple's hardcoded network restrictions.

### 2. Freeing Port 53 (Disabling systemd-resolved)

Ubuntu's default DNS stub listener occupies Port 53, preventing AdGuard Home from starting. Disabled it using these commands:

```bash
# Stop and disable the service
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Remove the symlink and create a static DNS config
sudo rm /etc/resolv.conf
sudo nvim /etc/resolv.conf

# Add these lines to the file to ensure the server still has internet:
nameserver 8.8.8.8
nameserver 1.1.1.1

```

### 3. AdGuard Home "Admin Port" Fix

The dashboard was inaccessible on port `8081` because the internal container configuration was wrong.

* **File:** `/srv/adguard/conf/AdGuardHome.yaml`
* **Fix:** Manually set the `http` address to Port 80 inside the container.

```yaml
http:
  address: 0.0.0.0:80  # Changed from 0.0.0.0:6060
  port: 80             # Changed from 8081

```

### 4. Nginx Proxy Manager (NPM) Settings

* **Forward IP:** Always use `192.168.1.32` instead of `localhost`.
* **Websockets Support:** Enabled for `ai.home` to allow real-time AI response streaming.

### 5. Git & Security Strategy

* **Secrets:** All credentials live in per-stack, gitignored `.env` files (`arcane/.env`, `npm/.env`, `watchtower/.env`, `homepage/.env`). Compose files interpolate from them via `env_file`; nothing sensitive is committed.
* **Arcane Keys:** `ENCRYPTION_KEY` and `JWT_SECRET` were previously committed (and pushed to GitHub). They have been rotated and moved to `arcane/.env`.
* **NPM DB Credentials:** `MYSQL_*` / `DB_MYSQL_*` moved to `npm/.env` with generated passwords, applied to the live MariaDB (`ALTER USER`).
* **Watchtower API Token:** stored in `watchtower/.env`; the Homepage widget reads the same value from `homepage/.env` (keep the two in sync).
* **AdGuard Config:** The live `AdGuardHome.yaml` stays gitignored (bcrypt hash). `adguard/conf/AdGuardHome.yaml.example` is tracked with the critical `http.address: 0.0.0.0:80` fix and the `.home` DNS rewrites so a rebuild is reproducible.
* **Ignored Directories:** `adguard/work/`, `adguard/data/`, `stremio/`, `arcane/data/`, `npm/data|letsencrypt|mysql`, `tailscale/state/`, `backups/`, and `**/logs/`.
* **NPM Admin:** The admin UI on port `81` has no IP restriction; restrict it via NPM Access Lists or `ufw allow from 192.168.1.0/24 to any port 81 proto tcp`.

### 6. Automated Maintenance
- **Watchtower**: Aims to automatically pull the latest base images for the dashboard/media/app containers.
  - **Port**: `9393` (Exposed for Homepage metrics API).
  - **API**: Secured via `WATCHTOWER_HTTP_API_TOKEN` (from `watchtower/.env`), mapped to Homepage to display live container scan statistics.
  - **Cleanup**: Configured to automatically delete stale images to prevent SSD bloat.
  - **Exclusions**: Critical / reconcilable-only services are pinned to image digests and carry `com.centurylinklabs.watchtower.enable=false` so they are **not** auto-updated: `adguardhome`, `tailscale`, `npm-app`, `npm-db`, `arcane`, `open-webui`. Watchtower only manages the remaining `:latest` services (`homepage`, `navidrome`, `stremio`, and itself).

### 7. Version Pinning

Infrastructure images are pinned by digest to the exact known-good version that was running (see each `docker-compose.yml`). To update a pinned service deliberately, replace the `@sha256:` digest (and tag) with a newer release's digest:

```bash
docker pull <image>:<new-version>
docker inspect --format '{{index .RepoDigests 0}}' <image>:<new-version>  # copy the @sha256 digest
# update the compose file, then `docker compose up -d`
```

### 8. Health Checks & Log Rotation

Every service now has a container healthcheck (checked via `docker ps`) so outages surface instead of failing silently, and `logging` limits each container to 3 x 10 MiB rotated JSON logs to prevent unbounded SSD growth.

### 9. Backups

`scripts/backup.sh` snapshots the data that isn't in git (env files, NPM config/certs/DB, AdGuard config, Navidrome DB, Arcane data, Stremio state, Tailscale state, and the Open-WebUI volume) into `/srv/backups/`, keeping the last 7. Media (`/data/music`, `/data/movies`) is intentionally excluded.

```bash
/srv/scripts/backup.sh
```

Recommended cron (runs nightly at 2:30 AM):
```cron
30 2 * * * /srv/scripts/backup.sh >> /srv/backups/backup.log 2>&1
```
