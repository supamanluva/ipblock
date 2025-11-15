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

## How to Run

### Option 1: Run with sudo
```bash
sudo bash update-scanner-block.sh
```

### Option 2: Make executable and run
```bash
chmod +x update-scanner-block.sh
sudo ./update-scanner-block.sh
```

## What This Script Does

1. **Creates ipsets** for scanners, country blocking, and whitelist
2. **Downloads** FireHOL IP blocklists (Levels 1, 2, and 3)
3. **Downloads country-specific IP blocks** (optional, configurable)
4. **Adds static scanner ranges** to the blocklist
5. **Whitelists** your VPN (10.8.0.0/16) and LAN (192.168.50.0/24) networks
6. **Deduplicates and cleans** IP entries
7. **Updates firewall rules** to:
   - Allow whitelisted IPs
   - Block scanner IPs in INPUT chain
   - Block scanner IPs in FORWARD chain (both src and dst)
   - Block country IPs (if configured)

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

⚠️ **WARNING**: This script modifies your firewall rules. Make sure you:
- Have physical or console access to your server
- Understand the networks being whitelisted (10.8.0.0/16 and 192.168.50.0/24)
- Test in a non-production environment first

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

To run this script automatically, add it to crontab:

```bash
sudo crontab -e
```

**Recommended schedules:**

Run weekly (Sundays at 3 AM):
```
0 3 * * 0 /home/rae/ipblock/update-scanner-block.sh >> /var/log/scanner-block.log 2>&1
```

Run daily at 3 AM (for high-security environments):
```
0 3 * * * /home/rae/ipblock/update-scanner-block.sh >> /var/log/scanner-block.log 2>&1
```

Run twice weekly (Sunday and Wednesday at 3 AM):
```
0 3 * * 0,3 /home/rae/ipblock/update-scanner-block.sh >> /var/log/scanner-block.log 2>&1
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
