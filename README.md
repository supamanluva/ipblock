# IP Block - Complete Server Protection

Multi-layer IP blocking and intrusion prevention for Linux servers.

## Quick Start

```bash
# Clone the repository
git clone https://github.com/supamanluva/ipblock.git
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
| Docker Protection | DOCKER-USER chain rules | Instant block |
| Docker Port Filter | Only expose needed ports | Port blocked |
| Rate Limiting | Connection floods | Temp block (24h) |
| fail2ban | Brute force attacks | Temp block (24h) |

---

## Manual Setup

If you prefer to set up components individually:

### Prerequisites

Before running scripts manually, ensure you have:

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

### Permissions

Scripts must be run with **root privileges** because they:
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

### Recommended Countries to Block

Based on analysis of real-world port scan and attack data, these countries are the most common sources of malicious traffic targeting servers:

| Code | Country | Attack Share | Common Attack Types |
|------|---------|-------------|---------------------|
| `cn` | China | ~17% | Port scanning, brute force, botnets |
| `ru` | Russia | ~8% | Port scanning, exploit attempts |
| `vn` | Vietnam | ~5% | SSH brute force, scanning |
| `id` | Indonesia | ~4% | Brute force, web exploits |
| `ir` | Iran | ~3% | Scanning, credential stuffing |
| `uz` | Uzbekistan | ~2% | SSH brute force |
| `bd` | Bangladesh | ~2% | Scanning, brute force |
| `eg` | Egypt | ~2% | Scanning, web exploits |
| `dz` | Algeria | ~1% | Scanning |
| `by` | Belarus | ~1% | Scanning, exploit attempts |
| `az` | Azerbaijan | ~1% | Scanning |
| `kp` | North Korea | <1% | State-sponsored scanning |

**Recommended configuration** (blocks ~45% of malicious traffic):
```bash
BLOCK_COUNTRIES="cn ru vn id ir uz bd eg dz by az kp"
```

> **Note**: The US (~30% of scan traffic) is not recommended for blocking since it hosts most legitimate services (GitHub, CDNs, APIs, etc.).

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

**Usage**:
```bash
sudo ./rate-limit-iptables.sh
```

**Configuration** (edit the script):
```bash
MAX_CONNECTIONS_PER_MINUTE=30    # Adjust based on your traffic
BURST_LIMIT=10                   # Allow initial burst
PROTECTED_PORTS="22,80,443,8080" # Ports to protect (empty = all)
```

**Monitor**:
```bash
sudo dmesg -w | grep -E 'RATE-LIMITED|CONNLIMIT|HASHLIMIT'
cat /proc/net/xt_recent/RATE_LIMIT
```

### Layer 2: Log-Based Rate Limiter (Cron-Based)

Analyzes access logs every 5 minutes and uses a **3-strike system** before blocking.

**Script**: `log-rate-limiter.sh`

**Detection Methods**:
- High request rate (>200 requests/5 min)
- 404 scanning (>10 not-found requests/min)
- Suspicious path access (wp-admin, .env, .git, etc.)
- Auth failures (SSH brute force)
- Repeated blocked attempts in kernel log

**Strike System**:
1. First offense → Strike 1 (logged)
2. Second offense → Strike 2 (logged)
3. Third offense → **24-hour IP ban**

**Usage**:
```bash
# Manual run
sudo ./log-rate-limiter.sh

# Install with cron (runs every 5 minutes)
sudo cp log-rate-limiter.sh /usr/local/bin/log-rate-limiter
echo "*/5 * * * * root /usr/local/bin/log-rate-limiter >> /var/log/rate-limiter.log 2>&1" | sudo tee /etc/cron.d/log-rate-limiter
```

**Configuration** (edit the script):
```bash
REQUESTS_PER_MINUTE=60          # Max requests per minute
REQUESTS_PER_5MIN=200           # Max requests per 5 minutes
BLOCK_DURATION=86400            # Block duration (24 hours)
ERROR_THRESHOLD=20              # Max errors per minute
REPEATED_404_THRESHOLD=10       # Max 404s per minute
```

**View offenders**:
```bash
cat /var/lib/ipblock/offenders.log
cat /var/lib/ipblock/strikes.db
```

### Layer 3: fail2ban Integration

Industry-standard intrusion prevention that monitors logs for malicious patterns.

**Script**: `fail2ban-setup.sh`

**Features**:
- SSH brute force protection (3 attempts = 24h ban)
- HTTP authentication failures
- Bot/scanner detection
- Recidive detection (repeat offenders get week-long bans)
- Uses ipset for efficient blocking

**Custom Jails Included**:
| Jail | Description | Max Retries | Ban Time |
|------|-------------|-------------|----------|
| `sshd` | SSH failures | 3 | 24 hours |
| `sshd-aggressive` | SSH repeat offenders | 1 | 7 days |
| `http-hammer` | HTTP request flood | 100/min | 24 hours |
| `http-scanner` | Vulnerability scanning | 5 | 24 hours |
| `recidive` | Repeat offenders | 3 bans | 7 days |

**Usage**:
```bash
sudo ./fail2ban-setup.sh
```

**Manage fail2ban**:
```bash
fail2ban-client status              # Show all jails
fail2ban-client status sshd         # Specific jail status
fail2ban-client set sshd banip IP   # Manually ban
fail2ban-client set sshd unbanip IP # Manually unban
fail2ban-client reload              # Reload config
```

### View All Blocks

**Script**: `show-blocked.sh`

Shows all currently blocked IPs across all ipsets with remaining ban time:

```bash
sudo ./show-blocked.sh
```

Output includes:
- Scanner blocklist entries
- Country blocks
- Rate-limited IPs (with expiry time)
- fail2ban blocks (with expiry time)
- Recent block events
- Statistics

### Manual IP Management

**Block an IP for 24 hours**:
```bash
sudo ipset add rate_limited 1.2.3.4
```

**Block an IP permanently** (until next blocklist update):
```bash
sudo ipset add scanners 1.2.3.4
```

**Unblock an IP**:
```bash
sudo ipset del rate_limited 1.2.3.4
sudo ipset del fail2ban 1.2.3.4
```

**Check if IP is blocked**:
```bash
sudo ipset test rate_limited 1.2.3.4
sudo ipset test scanners 1.2.3.4
```

### ipset Summary

| ipset Name | Purpose | Timeout |
|------------|---------|---------|
| `scanners` | FireHOL + static blocklists | Permanent |
| `country_block` | Country-based blocking | Permanent |
| `rate_limited` | Log-based rate limiter | 24 hours |
| `fail2ban` | fail2ban bans | 24 hours |
| `whitelist` | Never blocked IPs | Permanent |

### Monitoring

**Real-time block monitoring**:
```bash
sudo dmesg -w | grep -E 'SCANNER-BLOCKED|RATE-LIMITED|FAIL2BAN-BLOCKED'
```

**Rate limiter logs**:
```bash
sudo tail -f /var/log/rate-limiter.log
```

**fail2ban logs**:
```bash
sudo tail -f /var/log/fail2ban.log
```

### Recommended Configuration

For a typical web server:

1. **Run the master installer**:
   ```bash
   sudo ./install-rate-limiting.sh
   ```

2. **Tune thresholds** based on your traffic:
   - Low-traffic site: Lower thresholds (20 req/min)
   - High-traffic site: Higher thresholds (100+ req/min)

3. **Add to cron** for regular updates:
   ```bash
   # Update blocklists weekly
   0 3 * * 0 /usr/local/bin/update-scanner-blocklist.sh >> /var/log/scanner-block.log 2>&1
   
   # Rate limiter runs every 5 minutes (installed automatically)
   ```

4. **Whitelist your monitoring/health check IPs**:
   ```bash
   sudo ipset add whitelist YOUR_MONITORING_IP
   ```

---

## Port Scan Detection

Automatically detect and permanently block IPs that port scan your server.

### Quick Install

```bash
sudo ./portscan-detect.sh
```

### Detection Methods

| Method | Description | Action |
|--------|-------------|--------|
| **Stealth Scans** | NULL, XMAS, SYN/FIN scans | Logged & dropped |
| **Honeypot Ports** | Connections to unused trap ports | **Instant permanent block** |
| **Rapid Scanning** | 5+ ports in 60 seconds | Logged & dropped |
| **PSD Module** | Kernel-level scan detection | Logged & dropped |

### Honeypot Ports

Any connection to these ports results in an **instant permanent ban**:

| Port | Service | Port | Service |
|------|---------|------|---------|
| 23 | Telnet | 3389 | RDP |
| 135-139 | NetBIOS | 5432 | PostgreSQL |
| 445 | SMB | 5900 | VNC |
| 1433-1434 | MS-SQL | 6379 | Redis |
| 3306 | MySQL | 27017 | MongoDB |

**⚠️ Remove any ports you actually use!** Edit line 98 in `portscan-detect.sh`:
```bash
HONEYPOT_PORTS="23,135,137,138,139,445,1433,1434,3306,3389,5432,5900,6379,11211,27017"
```

### Persistence Across Reboots

Blocked IPs are saved hourly and restored on reboot via `/etc/cron.d/ipblock-persist`:
- Saves to `/etc/ipblock/portscan_blocked.save`
- Restores rules and blocked IPs on boot

---

## Docker Protection (DOCKER-USER Chain)

Docker published ports bypass the standard `INPUT` chain entirely — traffic goes through `FORWARD` → `DOCKER-USER` instead. This means standard iptables/ipset rules in the INPUT chain **do not protect** Docker containers with published ports.

The `update-scanner-block.sh` script automatically adds blocking rules to the `DOCKER-USER` chain, ensuring all ipset blocklists also protect Docker services.

### What's Protected

Traffic to Docker containers is filtered through the same blocklists:

| Rule | Action |
|------|--------|
| Established connections | RETURN (allow) |
| Whitelist IPs | RETURN (allow) |
| Country-blocked IPs | **DROP** |
| Known scanners | **DROP** |
| Port scan offenders | **DROP** |
| Allowed ports (80,443,81) | RETURN (allow) |
| Other ports from external IPs | **DROP** |
| Everything else | RETURN (allow) |

### How It Works

The script flushes and rebuilds `DOCKER-USER` on each run:

```bash
# Rules are applied in order (first match wins)
iptables -A DOCKER-USER -m state --state ESTABLISHED,RELATED -j RETURN
iptables -A DOCKER-USER -m set --match-set whitelist src -j RETURN
iptables -A DOCKER-USER -m set --match-set country_block src -j DROP
iptables -A DOCKER-USER -m set --match-set scanners src -j DROP
iptables -A DOCKER-USER -m set --match-set portscan_blocked src -j DROP
# Port filtering (added by docker-port-filter.sh):
iptables -A DOCKER-USER -p tcp -m multiport --dports 80,443,81 --ctstate NEW -j RETURN
iptables -A DOCKER-USER -p tcp --ctstate NEW ! internal-sources -j DROP
iptables -A DOCKER-USER -p udp --ctstate NEW ! internal-sources -j DROP
iptables -A DOCKER-USER -j RETURN
```

### Docker Port Filter

The `docker-port-filter.sh` script adds port-level access control to Docker containers. Docker bypasses UFW/INPUT chain entirely, so without this, **every published port is accessible from the internet** regardless of your firewall settings.

Configure allowed ports in `docker-port-filter.sh`:

```bash
ALLOWED_PORTS="80,443,81"  # Only these ports reachable from internet
```

All other Docker-published ports (Portainer, Zipline, app backends, etc.) remain accessible:
- Between containers on Docker networks
- From localhost
- From private IP ranges (10.x, 172.16-31.x, 192.168.x)

To add or change allowed ports:
```bash
# Edit the script
nano docker-port-filter.sh

# Re-apply
sudo ./docker-port-filter.sh
```

### Verify Docker Protection

```bash
# Check DOCKER-USER rules
sudo iptables -L DOCKER-USER -v -n

# See blocked packets (counters > 0 means it's working)
sudo iptables -L DOCKER-USER -v -n | grep DROP
```

> **Note**: Docker must be running for the `DOCKER-USER` chain to exist. The script skips Docker protection if the chain is not found.

---

## Quick Command Reference

### View Blocked IPs

```bash
# Show all blocks with summary
sudo ./show-blocked.sh

# List specific ipsets
sudo ipset list scanners           # FireHOL blocklist
sudo ipset list country_block      # Country blocks
sudo ipset list rate_limited       # Rate limited (24h)
sudo ipset list fail2ban           # fail2ban blocks
sudo ipset list portscan_blocked   # Port scanners (permanent)
sudo ipset list whitelist          # Whitelisted IPs
```

### Block/Unblock IPs

```bash
# Block an IP (24 hours)
sudo ipset add rate_limited 1.2.3.4

# Block a port scanner (permanent)
sudo ipset add portscan_blocked 1.2.3.4

# Block permanently in scanner list
sudo ipset add scanners 1.2.3.4

# Unblock an IP
sudo ipset del rate_limited 1.2.3.4
sudo ipset del portscan_blocked 1.2.3.4
sudo ipset del scanners 1.2.3.4

# Whitelist an IP (never blocked)
sudo ipset add whitelist 1.2.3.4
```

### Check if IP is Blocked

```bash
sudo ipset test scanners 1.2.3.4
sudo ipset test portscan_blocked 1.2.3.4
sudo ipset test rate_limited 1.2.3.4
```

### Real-Time Monitoring

```bash
# All blocked traffic
sudo dmesg -w | grep -E 'BLOCKED|SCAN|LIMIT|HONEYPOT'

# Scanner blocks only
sudo dmesg -w | grep 'SCANNER-BLOCKED'

# Port scan detections
sudo dmesg -w | grep -E 'PORTSCAN|HONEYPOT'

# Rate limiting
sudo dmesg -w | grep -E 'RATE-LIMITED|HASHLIMIT|CONNLIMIT'
```

### View Logs

```bash
# Kernel/firewall logs
sudo dmesg | grep -E 'BLOCKED|SCAN' | tail -50

# Rate limiter log
sudo tail -f /var/log/rate-limiter.log

# Port scan log
sudo tail -f /var/log/portscan.log

# fail2ban log
sudo tail -f /var/log/fail2ban.log

# Offender logs
cat /var/lib/ipblock/offenders.log
cat /var/lib/ipblock/portscan_offenders.log
```

### Statistics

```bash
# View iptables packet counts (INPUT chain)
sudo iptables -L INPUT -v -n | grep -E 'scanners|rate_limited|fail2ban|portscan'

# View Docker protection packet counts (DOCKER-USER chain)
sudo iptables -L DOCKER-USER -v -n | grep -E 'scanners|country_block|portscan'

# Count entries in each ipset
for set in scanners country_block rate_limited fail2ban portscan_blocked whitelist; do
  echo "$set: $(sudo ipset list $set 2>/dev/null | grep -c '^[0-9]' || echo 0) entries"
done
```

### fail2ban Commands

```bash
fail2ban-client status              # All jails
fail2ban-client status sshd         # SSH jail
fail2ban-client set sshd banip IP   # Manual ban
fail2ban-client set sshd unbanip IP # Manual unban
fail2ban-client reload              # Reload config
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
| `docker-port-filter.sh` | Restrict Docker ports accessible from internet |
| `install-rate-limiting.sh` | Installer for rate limiting only |
| `show-blocked.sh` | Display all blocked IPs |
| `check-blocking-status.sh` | Check firewall status |
| `verify-setup.sh` | Verify setup is complete |
| `test-country-block.sh` | Test country blocking |

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

Located in `/etc/cron.d/`:

```bash
# /etc/cron.d/ipblock-persist
0 * * * * root ipset save portscan_blocked > /etc/ipblock/portscan_blocked.save
@reboot root sleep 10 && /path/to/portscan-detect.sh

# /etc/cron.d/log-rate-limiter  
*/5 * * * * root /usr/local/bin/log-rate-limiter >> /var/log/rate-limiter.log

# Recommended: weekly blocklist update (add to root crontab)
0 3 * * 0 /path/to/update-scanner-block.sh >> /var/log/scanner-block.log 2>&1
```
