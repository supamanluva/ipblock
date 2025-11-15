# Scanner Blocklist Updater

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
