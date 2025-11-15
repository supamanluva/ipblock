#!/bin/bash
set -e

# -----------------------------
# Scanner Blocklist Updater
# -----------------------------
# ipset: scanners, country_block
# Whitelist: VPN 10.8.* and LAN 192.168.50.*
# -----------------------------

# Configuration: Add country codes to block (e.g., "cn ru ir kp")
# Leave empty to disable country blocking
BLOCK_COUNTRIES=""

# Create ipsets if missing
ipset create scanners hash:net -exist
ipset create country_block hash:net -exist
ipset create whitelist hash:net -exist

# Temporary file
TMP=$(mktemp)

# -----------------------------
# Download FireHOL IP lists
# -----------------------------
echo "Downloading FireHOL Level 1..."
curl -s http://iplists.firehol.org/files/firehol_level1.netset >> "$TMP"

echo "Downloading FireHOL Level 2..."
curl -s http://iplists.firehol.org/files/firehol_level2.netset >> "$TMP"

echo "Downloading FireHOL Level 3..."
curl -s http://iplists.firehol.org/files/firehol_level3.netset >> "$TMP"

# -----------------------------
# Add your static scanner ranges
# -----------------------------
cat <<EOF >> "$TMP"
66.132.159.0/24
162.142.125.0/24
167.94.138.0/24
167.94.145.0/24
167.94.146.0/24
167.248.133.0/24
199.45.154.0/24
199.45.155.0/24
206.168.34.0/24
206.168.35.0/24
198.20.69.74/31
198.20.69.96/28
198.20.70.112/29
66.111.4.0/23
104.244.72.0/22
216.186.32.0/21
60.191.36.0/22
223.112.96.0/21
169.55.19.0/24
169.55.20.0/24
208.68.37.0/24
208.68.38.0/24
198.20.69.74/32
198.20.69.98/32
198.20.99.130/32
93.120.27.62/32
66.240.236.119/32
71.6.135.131/32
66.240.192.138/32
71.6.167.142/32
82.221.105.6/32
82.221.105.7/32
71.6.165.200/32
188.138.9.50/32
85.25.103.50/32
85.25.43.94/32
71.6.146.185/32
71.6.158.166/32
198.20.87.98/32
209.126.110.38/32
66.240.219.146/32
104.236.198.48/32
104.131.0.69/32
162.159.244.38/32
184.105.247.196/32
141.212.122.112/32
125.237.220.106/32
192.81.128.37/32
74.82.47.2/32
216.218.206.66/32
184.105.139.67/32
54.81.158.232/32
141.212.122.144/32
141.212.122.128/32
54.206.70.29/32
184.105.139.0/24
216.218.206.0/24
74.82.47.0/24
184.105.247.0/24
65.49.20.0/24
65.49.1.0/24
64.62.156.0/24
64.62.197.0/24
EOF

# -----------------------------
# Whitelist VPN + LAN
# -----------------------------
ipset add whitelist 10.8.0.0/16 -exist
ipset add whitelist 192.168.50.0/24 -exist

# -----------------------------
# Download and load country blocks
# -----------------------------
if [ -n "$BLOCK_COUNTRIES" ]; then
    echo "Downloading country IP blocks..."
    COUNTRY_TMP=$(mktemp)
    
    for country in $BLOCK_COUNTRIES; do
        country_lower=$(echo "$country" | tr '[:upper:]' '[:lower:]')
        echo "  - Downloading ${country_lower^^} (${country_lower})..."
        curl -s "https://www.ipdeny.com/ipblocks/data/aggregated/${country_lower}-aggregated.zone" >> "$COUNTRY_TMP" 2>/dev/null || \
            echo "    Warning: Could not download ${country_lower}"
    done
    
    # Clean and load country blocks
    if [ -s "$COUNTRY_TMP" ]; then
        echo "Cleaning country block entries..."
        grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$COUNTRY_TMP" | sort -u > "${COUNTRY_TMP}.clean"
        
        echo "Flushing old country blocks..."
        ipset flush country_block
        
        echo "Loading country blocks..."
        while read -r net; do
            ipset add country_block "$net" -exist
        done < "${COUNTRY_TMP}.clean"
        
        echo "Loaded $(wc -l < ${COUNTRY_TMP}.clean) country networks."
        rm -f "$COUNTRY_TMP" "${COUNTRY_TMP}.clean"
    fi
fi

# -----------------------------
# Clean & dedupe IPs
# -----------------------------
echo "Cleaning entries..."
grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' "$TMP" \
    | sort -u > "${TMP}.clean"

# -----------------------------
# Flush old scanners ipset
# -----------------------------
echo "Flushing old entries..."
ipset flush scanners

# -----------------------------
# Load new IPs into scanners ipset
# -----------------------------
echo "Loading new entries..."
while read -r net; do
    ipset add scanners "$net" -exist
done < "${TMP}.clean"

# -----------------------------
# Always whitelist VPN/LAN IPs in scanners
# -----------------------------
ipset add scanners 10.8.0.0/16 -exist
ipset add scanners 192.168.50.0/24 -exist

# -----------------------------
# Setup iptables rules safely
# -----------------------------
# INPUT
iptables -C INPUT -m set --match-set whitelist src -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 1 -m set --match-set whitelist src -j ACCEPT

iptables -C INPUT -m set --match-set scanners src -j DROP 2>/dev/null || \
    iptables -A INPUT -m set --match-set scanners src -j DROP

# FORWARD
iptables -C FORWARD -m set --match-set whitelist src -j ACCEPT 2>/dev/null || \
    iptables -I FORWARD 1 -m set --match-set whitelist src -j ACCEPT

iptables -C FORWARD -m set --match-set scanners src -j DROP 2>/dev/null || \
    iptables -A FORWARD -m set --match-set scanners src -j DROP

iptables -C FORWARD -m set --match-set scanners dst -j DROP 2>/dev/null || \
    iptables -A FORWARD -m set --match-set scanners dst -j DROP

# Country blocking rules (if enabled)
if [ -n "$BLOCK_COUNTRIES" ]; then
    iptables -C INPUT -m set --match-set country_block src -j DROP 2>/dev/null || \
        iptables -A INPUT -m set --match-set country_block src -j DROP

    iptables -C FORWARD -m set --match-set country_block src -j DROP 2>/dev/null || \
        iptables -A FORWARD -m set --match-set country_block src -j DROP

    iptables -C FORWARD -m set --match-set country_block dst -j DROP 2>/dev/null || \
        iptables -A FORWARD -m set --match-set country_block dst -j DROP
fi

# -----------------------------
# Done
# -----------------------------
echo "Done. Loaded $(wc -l < ${TMP}.clean) networks into 'scanners' ipset."
rm -f "$TMP" "${TMP}.clean"
