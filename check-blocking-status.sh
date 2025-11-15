#!/bin/bash

# Real-world country blocking test

echo "=== Real-World Country Blocking Test ==="
echo ""
echo "Current BLOCK_MODE: $(grep '^BLOCK_MODE=' /home/rae/ipblock/update-scanner-block.sh | cut -d'"' -f2)"
echo ""

# Check iptables rules
echo "=== Active Firewall Rules ==="
echo "INPUT chain (blocks NEW incoming from blocked countries):"
sudo iptables -L INPUT -v -n | grep country_block
echo ""

echo "FORWARD chain (blocks routing to/from blocked countries):"
sudo iptables -L FORWARD -v -n | grep country_block || echo "  (none - BLOCK_MODE=incoming only blocks INPUT)"
echo ""

# Check blocked packet statistics
echo "=== Statistics ==="
SCANNER_BLOCKED=$(sudo iptables -L INPUT -v -n | grep "match-set scanners" | awk '{print $1}')
COUNTRY_BLOCKED=$(sudo iptables -L INPUT -v -n | grep "match-set country_block" | awk '{print $1}')

echo "Packets blocked from scanner IPs: $SCANNER_BLOCKED"
echo "Packets blocked from blocked countries: $COUNTRY_BLOCKED"
echo ""

# Show recent blocks
echo "=== Recent Blocked Attempts (last 10) ==="
sudo dmesg | grep "SCANNER-BLOCKED" | tail -10 | while read line; do
    SRC=$(echo "$line" | grep -oP 'SRC=\K[0-9.]+')
    DST=$(echo "$line" | grep -oP 'DST=\K[0-9.]+')
    PROTO=$(echo "$line" | grep -oP 'PROTO=\K[A-Z]+')
    DPT=$(echo "$line" | grep -oP 'DPT=\K[0-9]+')
    echo "  Blocked: $SRC → $DST ($PROTO port $DPT)"
done

echo ""
echo "=== How to Monitor in Real-Time ==="
echo "Run this command in another terminal:"
echo "  sudo dmesg -w | grep 'SCANNER-BLOCKED'"
echo ""
echo "Then try to scan your server from an external IP to see it get blocked."
