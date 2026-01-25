# IP Block - Complete Server Protection

Multi-layer IP blocking and intrusion prevention for Linux servers.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/ipblock.git
cd ipblock

# Run the master setup script
sudo ./setup.sh
```

That's it! The setup script will:
- Install prerequisites (ipset, iptables)
- Download and apply scanner blocklists (FireHOL Level 1-3)
- Configure port scan detection with honeypot traps
- Set up kernel-level rate limiting
- Install log-based rate limiter (cron-based, 3-strike system)
- Optionally configure fail2ban
- Set up weekly automatic updates
- Save rules for persistence across reboots

---

## What's Protected

| Layer | Protection | Response |
|-------|------------|----------|
| Scanner Blocklists | Known malicious IPs | Instant block |
| Country Blocking | Geographic filtering | Instant block |
| Port Scan Detection | Honeypot traps | **Permanent ban** |
| Rate Limiting | Connection floods | Temp block (24h) |
| fail2ban | Brute force attacks | Temp block (24h) |

---

## Manual Setup

If you prefer to set up components individually:

### Prerequisites

## Prerequisites

Before running `update-scanner-block.sh`, ensure you have the following installed:

1. **ipset** - IP set administration tool
   ```bash
   sudo apt install ipset
   ```

2. **iptables** - Firewall administration tool (usually pre-installed)
   ```bash
   sudo apt install iptables
   ```

3. **curl** - Tool for downloading files
   ```bash
   sudo apt install curl
   ```

## Permissions

This script must be run with **root privileges** because it:
- Creates and modifies ipset tables
- Modifies iptables firewall rules
- Flushes existing firewall configurations

## Installation

### Install to System Path (Recommended)

For easier execution and cron automation, install the script to `/usr/local/bin/`:

```bash
sudo cp update-scanner-block.sh /usr/local/bin/update-scanner-blocklist.sh
sudo chmod +x /usr/local/bin/update-scanner-blocklist.sh
```

Then you can run it from anywhere:
```bash
sudo update-scanner-blocklist.sh
```

### Alternative: Run from Current Directory

#### Option 1: Run with sudo
```bash
sudo bash update-scanner-block.sh
```

#### Option 2: Make executable and run
```bash
chmod +x update-scanner-block.sh
sudo ./update-scanner-block.sh
```

## What This Script Does

1. **Creates ipsets** for scanners, country blocking, and whitelist
2. **Sets up connection tracking** - allows all established/related connections (critical!)
3. **Downloads** FireHOL IP blocklists (Levels 1, 2, and 3)
4. **Downloads country-specific IP blocks** (optional, configurable)
5. **Adds static scanner ranges** to the blocklist
6. **Whitelists** your current public IP, VPN (10.8.0.0/16) and LAN (192.168.50.0/24) networks
7. **Deduplicates and cleans** IP entries
8. **Updates firewall rules** to:
   - Allow all ESTABLISHED and RELATED connections (your outbound traffic responses)
   - Allow localhost traffic
   - Allow whitelisted IPs
   - Block **only NEW** incoming connections from scanners (not responses to your requests)
   - Optionally block country IPs (if configured)

### Block Modes

Edit the `BLOCK_MODE` variable in the script:

- **`disabled`** - Downloads and loads blocklists but doesn't apply any firewall rules (for testing)
- **`incoming`** (default) - Blocks NEW incoming connections only. Safe for workstations.
- **`router`** - Blocks both incoming and forwarding. Use on routers/gateways/firewalls.

### Logging

Set `ENABLE_LOGGING="yes"` in the script to log blocked packets. View logs with:
```bash
sudo dmesg | grep "SCANNER-BLOCKED"
```

Or monitor in real-time:
```bash
sudo tail -f /var/log/kern.log | grep "SCANNER-BLOCKED"
```

## Country Blocking Feature

### Enable Country Blocking

To block specific countries, edit the script and set the `BLOCK_COUNTRIES` variable at the top:

```bash
# Example: Block China, Russia, Iran, and North Korea
BLOCK_COUNTRIES="cn ru ir kp"
```

### Available Country Codes

Use ISO 3166-1 alpha-2 country codes (two-letter codes). Common examples:

| Code | Country | Code | Country | Code | Country |
|------|---------|------|---------|------|---------|
| `cn` | China | `ru` | Russia | `ir` | Iran |
| `kp` | North Korea | `br` | Brazil | `in` | India |
| `pk` | Pakistan | `tr` | Turkey | `ua` | Ukraine |
| `vn` | Vietnam | `id` | Indonesia | `th` | Thailand |

**Full list available at**: https://www.ipdeny.com/ipblocks/

### How Country Blocking Works

1. Downloads aggregated IP ranges from IPDeny.com for specified countries
2. Creates a separate `country_block` ipset
3. Adds iptables rules to DROP traffic from/to blocked countries
4. **Whitelist takes priority** - your VPN/LAN will never be blocked

### Disable Country Blocking

Leave the variable empty:
```bash
BLOCK_COUNTRIES=""
```

## Important Notes

⚠️ **CRITICAL SAFETY FEATURES**:
- Script automatically detects and whitelists your current public IP
- Whitelist rules are applied FIRST before any blocking rules
- VPN (10.8.0.0/16) and LAN (192.168.50.0/24) are always allowed
- If you lose connection, flush rules: `sudo iptables -F INPUT && sudo iptables -F FORWARD`

⚠️ **WARNING**: This script modifies your firewall rules. Make sure you:
- Have physical or console access to your server
- Understand the networks being whitelisted
- Test in a non-production environment first
- Know how to restore access if something goes wrong

## Persistence

The iptables rules created by this script are **not persistent** across reboots by default. To make them persistent:

### On Debian/Ubuntu:
```bash
sudo apt install iptables-persistent
sudo netfilter-persistent save
```

### Using ipset-persistent:
```bash
sudo apt install ipset-persistent
sudo service netfilter-persistent save
```

## Automating Updates

**RECOMMENDED**: Run this script at least once per week to keep blocklists up-to-date. FireHOL and IPDeny lists are regularly updated with new threats and country IP ranges.

### Setup Instructions

1. **Install script to system path** (if not already done):
   ```bash
   sudo cp update-scanner-block.sh /usr/local/bin/update-scanner-blocklist.sh
   sudo chmod +x /usr/local/bin/update-scanner-blocklist.sh
   ```

2. **Open root crontab**:
   ```bash
   sudo crontab -e
   ```

3. **Add one of the schedules below** to the crontab file:

**Recommended schedules:**

Run weekly (Sundays at 3 AM):
```
0 3 * * 0 /usr/local/bin/update-scanner-blocklist.sh >> /var/log/scanner-block.log 2>&1
```

Run daily at 3 AM (for high-security environments):
```
0 3 * * * /usr/local/bin/update-scanner-blocklist.sh >> /var/log/scanner-block.log 2>&1
```

Run twice weekly (Sunday and Wednesday at 3 AM):
```
0 3 * * 0,3 /usr/local/bin/update-scanner-blocklist.sh >> /var/log/scanner-block.log 2>&1
```

4. **Save and exit** the crontab editor (in nano: `Ctrl+X`, then `Y`, then `Enter`)

5. **Verify crontab is set**:
   ```bash
   sudo crontab -l
   ```

## Troubleshooting

If the script fails:
- Check if ipset is installed: `which ipset`
- Check if you have root access: `sudo -v`
- View current ipset tables: `sudo ipset list`
- View current iptables rules: `sudo iptables -L -n -v`
- Check country code is valid: visit https://www.ipdeny.com/ipblocks/
- Test country download manually: `curl -s https://www.ipdeny.com/ipblocks/data/aggregated/cn-aggregated.zone`

## Additional Features & Resources

### FireHOL IP Lists
Your script uses FireHOL Level 1, 2, and 3. More lists available at:
- **Website**: https://iplists.firehol.org/
- **Available lists**: Malware, botnets, anonymous proxies, tor exits, and more
- **Usage**: Simply add more `curl` commands in the script pointing to other `.netset` files

### IPDeny Country Lists
- **Website**: https://www.ipdeny.com/ipblocks/
- **Aggregated zones**: Optimized for better performance (used in this script)
- **All zones archive**: Download all countries at once with `all-zones.tar.gz`
- **IPv6 support**: Available separately

### Example: Add More FireHOL Lists

To add more threat intelligence, insert these after the Level 3 download:

```bash
echo "Downloading FireHOL Anonymous Proxies..."
curl -s http://iplists.firehol.org/files/firehol_anonymous.netset >> "$TMP"

echo "Downloading FireHOL Webserver..."
curl -s http://iplists.firehol.org/files/firehol_webserver.netset >> "$TMP"
```

---

## Rate Limiting & Hammering Protection

In addition to static blocklists, this project includes **dynamic rate limiting** to detect and block IPs that hammer your server. Three layers of protection work together:

### Quick Install

```bash
sudo ./install-rate-limiting.sh
```

This installs all three protection layers with sensible defaults.

### Layer 1: iptables Rate Limiting (Kernel-Level)

Real-time protection using iptables modules. No log parsing needed.

**Script**: `rate-limit-iptables.sh`

**Features**:
- **Recent module**: Max 30 new connections/minute per IP
- **Connlimit**: Max 50 concurrent connections per IP
- **Hashlimit**: Sophisticated rate limiting with burst protection

### Layer 2: Log-Based Rate Limiting

Analyzes web server logs to detect and block IPs making excessive requests.

**Script**: `log-rate-limiter.sh`

**Features**:
- Monitors nginx/Apache access logs
- 3-strike system before blocking
- Configurable thresholds (default: 100 requests/minute)
- 24-hour blocks via `rate_limited` ipset

### Layer 3: fail2ban Integration

Advanced protection with regex-based log analysis.

**Script**: `fail2ban-setup.sh`

---

## Port Scan Detection

Automatically detects and **permanently blocks** IPs performing port scans against your server.

### Setup

```bash
sudo ./portscan-detect.sh
```

### Detection Methods

1. **PSD (Port Scan Detection) Module** - Detects rapid port probing
2. **Recent Module** - Tracks connection attempts, blocks after threshold
3. **Honeypot Ports** - Instant permanent ban for connecting to:
   - 23 (Telnet), 135/137-139/445 (Windows/SMB)
   - 1433/1434 (MSSQL), 3306 (MySQL), 5432 (PostgreSQL)
   - 3389 (RDP), 5900 (VNC), 6379 (Redis)
   - 11211 (Memcached), 27017 (MongoDB)
4. **Stealth Scan Detection** - NULL, XMAS, SYN/FIN packets

### Log Analyzer

Runs via cron to catch patterns the iptables rules miss:

```bash
echo "*/10 * * * * root /path/to/portscan-log-analyzer.sh" | sudo tee /etc/cron.d/portscan-analyzer
```

### View Port Scan Blocks

```bash
# All permanently blocked scanners
sudo ipset list portscan_blocked

# Recent detections
sudo dmesg | grep -E 'PORTSCAN|HONEYPOT|STEALTH' | tail -20
```

---

## Quick Command Reference

### View All Blocked IPs

```bash
# Show everything with the nice script
sudo ./show-blocked.sh

# Or manually check each ipset
sudo ipset list scanners          # FireHOL blocklists
sudo ipset list country_block     # Country blocks
sudo ipset list portscan_blocked  # Port scanners (permanent)
sudo ipset list rate_limited      # HTTP hammering (24h)
sudo ipset list fail2ban          # Brute force (24h)
```

### Block/Unblock IPs Manually

```bash
# Add IP to scanner block (permanent)
sudo ipset add scanners 1.2.3.4

# Add IP to port scan block (permanent)
sudo ipset add portscan_blocked 1.2.3.4

# Remove an IP
sudo ipset del scanners 1.2.3.4
sudo ipset del portscan_blocked 1.2.3.4

# Whitelist an IP (never blocked)
sudo ipset add whitelist 1.2.3.4
```

### Check If IP Is Blocked

```bash
# Test specific IP
sudo ipset test scanners 1.2.3.4
sudo ipset test portscan_blocked 1.2.3.4

# Search all ipsets for an IP
for set in scanners country_block portscan_blocked rate_limited fail2ban whitelist; do
  sudo ipset test $set 1.2.3.4 2>/dev/null && echo "Found in: $set"
done
```

### Monitor Live Blocks

```bash
# Watch for new blocks
sudo dmesg -w | grep -E 'SCANNER-BLOCK|PORTSCAN|HONEYPOT|RATE-LIMITED'

# Recent iptables activity
sudo iptables -L -n -v | head -50
```

### fail2ban Commands

```bash
fail2ban-client status              # All jails
fail2ban-client status sshd         # SSH jail
fail2ban-client set sshd banip IP   # Manual ban
fail2ban-client set sshd unbanip IP # Manual unban
```

---

## All Scripts Reference

| Script | Purpose |
|--------|---------|
| `setup.sh` | **Master setup - run this first!** |
| `update-scanner-block.sh` | Download and apply FireHOL blocklists |
| `portscan-detect.sh` | Setup port scan detection rules |
| `portscan-log-analyzer.sh` | Analyze logs for scan patterns (cron) |
| `rate-limit-iptables.sh` | Setup iptables rate limiting |
| `log-rate-limiter.sh` | Analyze logs for hammering (cron) |
| `fail2ban-setup.sh` | Install and configure fail2ban |
| `install-rate-limiting.sh` | Installer for rate limiting only |
| `show-blocked.sh` | Display all blocked IPs |
| `check-blocking-status.sh` | Check firewall status |
| `test-country-block.sh` | Test country blocking |
| `verify-setup.sh` | Verify setup is complete |

---

## ipset Summary

| ipset Name | Purpose | Timeout | Source |
|------------|---------|---------|--------|
| `scanners` | FireHOL + static IPs | Permanent | `update-scanner-block.sh` |
| `country_block` | Country IP ranges | Permanent | `update-scanner-block.sh` |
| `rate_limited` | HTTP hammering | 24 hours | `log-rate-limiter.sh` |
| `fail2ban` | Brute force attacks | 24 hours | fail2ban |
| `portscan_blocked` | Port scanners | **Permanent** | `portscan-detect.sh` |
| `whitelist` | Never blocked | Permanent | `update-scanner-block.sh` |

---

## Cron Jobs

```bash
# /etc/cron.d/ipblock-persist - Persistence across reboots
0 * * * * root ipset save portscan_blocked > /etc/ipblock/portscan_blocked.save
@reboot root sleep 10 && /home/rae/ipblock/portscan-detect.sh

# Recommended: weekly blocklist update
0 3 * * 0 /home/rae/ipblock/update-scanner-block.sh >> /var/log/scanner-block.log 2>&1
```

---

## Verify Setup

After installation, run the verification script to ensure everything is configured correctly:

```bash
sudo ./verify-setup.sh
```

This checks:
- ✓ Required tools (ipset, iptables, curl)
- ✓ All ipset tables exist and have entries
- ✓ iptables rules are active
- ✓ Cron jobs for persistence
- ✓ Recent blocking activity
- ✓ Quick stats summary

Example output:
```
═══ ipset Tables ═══
  ✓ scanners exists (45000 entries)
  ✓ portscan_blocked exists - permanent (12 entries)
  ✓ whitelist exists (5 entries)

═══ Quick Stats ═══
  Total IPs/ranges blocked: 45017
  
  Passed:  15
  Warnings: 2
  Failed:  0

⚠ Setup is functional with some optional features missing.
```
