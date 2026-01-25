#!/bin/bash

# -----------------------------
# Show All Blocked IPs
# -----------------------------
# Displays IPs blocked by all systems with remaining time
# -----------------------------

echo "=============================================="
echo "  Current IP Blocks Summary"
echo "=============================================="
echo ""

# Function to show ipset with timeout info
show_ipset() {
    local name="$1"
    local description="$2"
    
    if ! ipset list "$name" &>/dev/null; then
        echo "$description: (ipset not found)"
        return
    fi
    
    local count=$(ipset list "$name" 2>/dev/null | grep -cE '^[0-9]' || echo "0")
    echo "=== $description ($count entries) ==="
    
    if [ "$count" -gt 0 ] && [ "$count" -lt 50 ]; then
        ipset list "$name" 2>/dev/null | grep -E '^[0-9]' | head -20 | while read line; do
            ip=$(echo "$line" | awk '{print $1}')
            timeout=$(echo "$line" | grep -oE 'timeout [0-9]+' | awk '{print $2}')
            
            if [ -n "$timeout" ]; then
                hours=$((timeout / 3600))
                mins=$(((timeout % 3600) / 60))
                echo "  $ip (expires in ${hours}h ${mins}m)"
            else
                echo "  $ip (permanent)"
            fi
        done
        [ "$count" -gt 20 ] && echo "  ... and $((count - 20)) more"
    elif [ "$count" -ge 50 ]; then
        echo "  (too many to list - showing count only)"
    else
        echo "  (empty)"
    fi
    echo ""
}

# Show all ipsets
show_ipset "scanners" "Scanner Blocklist (FireHOL + static)"
show_ipset "country_block" "Country Blocks"
show_ipset "rate_limited" "Rate Limited (24h auto-expire)"
show_ipset "fail2ban" "fail2ban Blocks (24h auto-expire)"
show_ipset "portscan_blocked" "Port Scanners (24h auto-expire)"
show_ipset "whitelist" "Whitelisted IPs (never blocked)"

# Show recent block events
echo "=== Recent Block Events (last 20) ==="
sudo dmesg 2>/dev/null | grep -E 'SCANNER-BLOCKED|RATE-LIMITED|RATELIMIT-BLOCKED|FAIL2BAN-BLOCKED|CONNLIMIT|HASHLIMIT|PORTSCAN|HONEYPOT|NULL-SCAN|XMAS-SCAN|SYNFIN-SCAN' | tail -20 | while read line; do
    timestamp=$(echo "$line" | grep -oE '^\[[^]]+\]' || echo "")
    prefix=$(echo "$line" | grep -oE '(SCANNER|RATE|FAIL2BAN|CONNLIMIT|HASHLIMIT|PORTSCAN|HONEYPOT|NULL-SCAN|XMAS-SCAN|SYNFIN)[^:]*' | head -1 || echo "UNKNOWN")
    src=$(echo "$line" | grep -oE 'SRC=[0-9.]+' | cut -d= -f2)
    dst=$(echo "$line" | grep -oE 'DST=[0-9.]+' | cut -d= -f2)
    dpt=$(echo "$line" | grep -oE 'DPT=[0-9]+' | cut -d= -f2)
    
    if [ -n "$src" ]; then
        echo "  $prefix: $src → $dst:$dpt"
    fi
done

echo ""
echo "=== Statistics ==="
echo "Packets blocked (scanners):      $(sudo iptables -L INPUT -v -n 2>/dev/null | grep 'match-set scanners' | awk '{print $1}' | head -1)"
echo "Packets blocked (rate_limited):  $(sudo iptables -L INPUT -v -n 2>/dev/null | grep 'match-set rate_limited' | awk '{print $1}' | head -1)"
echo "Packets blocked (fail2ban):      $(sudo iptables -L INPUT -v -n 2>/dev/null | grep 'match-set fail2ban' | awk '{print $1}' | head -1)"
echo "Packets blocked (portscan):      $(sudo iptables -L INPUT -v -n 2>/dev/null | grep 'match-set portscan_blocked' | awk '{print $1}' | head -1)"
echo ""

# fail2ban status if available
if command -v fail2ban-client &>/dev/null; then
    echo "=== fail2ban Status ==="
    fail2ban-client status 2>/dev/null | grep -E 'Jail list|Number of jail' || echo "  fail2ban not running"
    echo ""
fi

echo "=== Quick Commands ==="
echo "Monitor live:       sudo dmesg -w | grep -E 'BLOCKED|SCAN|LIMIT'"
echo "Block IP 24h:       sudo ipset add rate_limited 1.2.3.4"
echo "Block port scanner: sudo ipset add portscan_blocked 1.2.3.4"
echo "Unblock IP:         sudo ipset del rate_limited 1.2.3.4"
echo "Check if blocked:   sudo ipset test rate_limited 1.2.3.4"
