# My Nitro 5 HomeServer

A pure-Docker infrastructure running on an Acer Nitro 5 (**192.168.1.32**). This repository serves as a backup for configurations and a technical guide for the stack.

## Network Architecture

The network follows a three-step handshake to enable clean `.local` URLs house-wide:

1. **ZTE Router:** DHCP Primary DNS set to `192.168.1.32` and **ISP DNS** toggled **Off**.
2. **AdGuard Home:** Acts as the DNS resolver, rewriting `.local` domains to the server IP.
3. **Nginx Proxy Manager (NPM):** Acts as the reverse proxy, routing traffic from Port 80 to specific service ports.

## 🛠 Services & Local URLs

| Service | Host Port | Local URL | Description |
| --- | --- | --- | --- |
| **NPM** | 81 | `http://192.168.1.32:81` | Reverse Proxy Management |
| **AdGuard** | 8081 | `http://192.168.1.32:8081` | Network-wide DNS & Ad-blocking |
| **Homepage** | 3001 | `http://home.local` | Central Service Dashboard |
| **Arcane** | 3552 | `http://arcane.local` | Personal RAG Dashboard |
| **Open-WebUI** | 3000 | `http://ai.local` | AI Chat Interface (Websockets enabled) |
| **Navidrome** | 4533 | `http://music.local` | Music Streaming Server |
| **Stremio** | 8080 | `http://stremio.local` | Media Streaming Service |

## ⚙️ Technical Implementation & Fixes

### 1. Freeing Port 53 (Disabling systemd-resolved)

Ubuntu's default DNS stub listener occupies Port 53, preventing AdGuard Home from starting. We disabled it using these commands:

```bash
# Stop and disable the service
sudo systemctl stop systemd-resolved
sudo systemctl disable systemd-resolved

# Remove the symlink and create a static DNS config
sudo rm /etc/resolv.conf
sudo nano /etc/resolv.conf

# Add these lines to the file to ensure the server still has internet:
nameserver 8.8.8.8
nameserver 1.1.1.1

```


### 2. AdGuard Home "Admin Port" Fix

The dashboard was inaccessible on port `8081` because the internal container configuration was wrong.

* **File:** `/srv/adguard/conf/AdGuardHome.yaml`
* **Fix:** Manually set the `http` address to Port 80 inside the container.
```yaml
http:
  address: 0.0.0.0:80  # Changed from 0.0.0.0:6060
  port: 80             # Changed from 8081

```


### 3. Nginx Proxy Manager (NPM) Settings

* **Forward IP:** Always use `192.168.1.32`.
* **Websockets Support:** Enabled for `ai.local` to allow real-time AI response streaming.


### 4. Git & Security Strategy

* **Sensitive Data:** `AdGuardHome.yaml` and `.env` files are in `.gitignore` to protect password hashes.
* **Ignored Directories:** `adguard/work/`, `adguard/data/`, and `**/logs/`.

