#!/bin/bash

# -----------------------------
# Port Scan Log Analyzer
# -----------------------------
# Analyzes kernel logs for port scan patterns
# Automatically blocks offenders after 3 strikes
# Run via cron every 5 minutes
# -----------------------------

# Configuration
# BLOCK_DURATION - now permanent          # Block for 24 hours
STRIKE_THRESHOLD=3            # Strikes before blocking
STATE_DIR="/var/lib/ipblock"
PORTSCAN_STRIKES="$STATE_DIR/portscan_strikes.db"
PORTSCAN_LOG="$STATE_DIR/portscan_offenders.log"

# Create directories and files
mkdir -p "$STATE_DIR"
touch "$PORTSCAN_STRIKES"

# Create ipset if not exists
ipset create portscan_blocked hash:net  -exist

echo "$(date '+%Y-%m-%d %H:%M:%S') - Analyzing logs for port scans..."

# Function to add strike and possibly block
add_portscan_strike() {
    local ip="$1"
    local reason="$2"
    local current_time=$(date +%s)
    
    # Skip if already blocked
    if ipset test portscan_blocked "$ip" 2>/dev/null; then
        return 0
    fi
    
    # Skip whitelisted IPs
    if ipset test whitelist "$ip" 2>/dev/null; then
        return 0
    fi
    
    # Count recent strikes (last hour)
    local strikes=$(grep "^$ip " "$PORTSCAN_STRIKES" 2>/dev/null | \
        awk -v cutoff=$((current_time - 3600)) '$2 > cutoff {count++} END {print count+0}')
    
    # Add new strike
    echo "$ip $current_time $reason" >> "$PORTSCAN_STRIKES"
    strikes=$((strikes + 1))
    
    echo "  Strike $strikes for $ip: $reason"
    
    # Block after threshold
    if [ "$strikes" -ge "$STRIKE_THRESHOLD" ]; then
        echo "  >>> BLOCKING $ip for 24 hours (port scanning)"
        ipset add portscan_blocked "$ip"  -exist
        echo "$(date '+%Y-%m-%d %H:%M:%S') BLOCKED $ip - $reason (strikes: $strikes)" >> "$PORTSCAN_LOG"
    fi
}

# Analyze dmesg for port scan patterns
analyze_portscan_logs() {
    echo "Checking for port scan activity..."
    
    # Get IPs from PORTSCAN log entries
    dmesg 2>/dev/null | grep -E 'PORTSCAN:|HONEYPOT-HIT:' | \
        grep -oE 'SRC=[0-9.]+' | cut -d= -f2 | \
        sort | uniq -c | sort -rn | \
        while read count ip; do
            if [ "$count" -gt 2 ]; then
                add_portscan_strike "$ip" "Port scan detected: $count hits"
            fi
        done
    
    # Get IPs from stealth scan entries
    echo "Checking for stealth scan activity..."
    dmesg 2>/dev/null | grep -E 'NULL-SCAN:|XMAS-SCAN:|SYNFIN-SCAN:|SYNRST-SCAN:|FINRST-SCAN:' | \
        grep -oE 'SRC=[0-9.]+' | cut -d= -f2 | \
        sort | uniq -c | sort -rn | \
        while read count ip; do
            if [ "$count" -gt 0 ]; then
                add_portscan_strike "$ip" "Stealth scan detected: $count attempts"
            fi
        done
    
    # Analyze connection attempts to many different ports from same IP
    echo "Checking for multi-port connection attempts..."
    dmesg 2>/dev/null | grep -E 'SCANNER-BLOCKED:|PORTSCAN:' | \
        while read line; do
            src=$(echo "$line" | grep -oE 'SRC=[0-9.]+' | cut -d= -f2)
            dpt=$(echo "$line" | grep -oE 'DPT=[0-9]+' | cut -d= -f2)
            if [ -n "$src" ] && [ -n "$dpt" ]; then
                echo "$src $dpt"
            fi
        done | sort | uniq | \
        awk '{ports[$1]++} END {for (ip in ports) if (ports[ip] > 5) print ports[ip], ip}' | \
        sort -rn | \
        while read count ip; do
            add_portscan_strike "$ip" "Multi-port scan: $count different ports"
        done
}

# Cleanup old strikes (keep last 2 hours)
cleanup_portscan_strikes() {
    local current_time=$(date +%s)
    local cutoff=$((current_time - 7200))
    
    if [ -f "$PORTSCAN_STRIKES" ]; then
        awk -v cutoff="$cutoff" '$2 > cutoff' "$PORTSCAN_STRIKES" > "${PORTSCAN_STRIKES}.tmp" 2>/dev/null
        mv "${PORTSCAN_STRIKES}.tmp" "$PORTSCAN_STRIKES" 2>/dev/null || true
    fi
}

# Main
cleanup_portscan_strikes
analyze_portscan_logs

# Summary
BLOCKED_COUNT=$(ipset list portscan_blocked 2>/dev/null | grep -cE '^[0-9]' || echo "0")
echo ""
echo "=== Summary ==="
echo "IPs blocked for port scanning: $BLOCKED_COUNT"
echo "Strike database entries: $(wc -l < "$PORTSCAN_STRIKES" 2>/dev/null || echo 0)"
echo ""
echo "Recent blocks:"
tail -5 "$PORTSCAN_LOG" 2>/dev/null || echo "  (none yet)"
