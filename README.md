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

* **Sensitive Data:** `AdGuardHome.yaml` and `.env` files are in `.gitignore` to protect password hashes.
* **Ignored Directories:** `adguard/work/`, `adguard/data/`, and `**/logs/`.
