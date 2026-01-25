#!/bin/bash
set -e

# -----------------------------
# iptables Rate Limiting Setup
# -----------------------------
# Uses the "recent" module for real-time connection tracking
# No log parsing needed - kernel-level rate limiting
# -----------------------------

# Configuration
MAX_CONNECTIONS_PER_MINUTE=30    # Max new connections per minute per IP
BURST_LIMIT=10                   # Max burst of connections in short window
BLOCK_SECONDS=3600               # Block for 1 hour after exceeding limit (iptables recent)

# Ports to protect (comma-separated, empty = all ports)
PROTECTED_PORTS="22,80,443,8080"

echo "=== iptables Rate Limiting Setup ==="
echo "Max connections/minute: $MAX_CONNECTIONS_PER_MINUTE"
echo "Burst limit: $BURST_LIMIT"
echo "Protected ports: ${PROTECTED_PORTS:-all}"
echo ""

# Create rate_limited ipset for longer-term blocks (24 hours via cron cleanup)
ipset create rate_limited hash:net timeout 86400 -exist

# Whitelist check - never rate limit whitelisted IPs
iptables -C INPUT -m set --match-set whitelist src -j ACCEPT 2>/dev/null || \
    echo "Note: Whitelist rule should already exist from update-scanner-block.sh"

# -----------------------------
# Method 1: Recent module rate limiting
# Tracks connection attempts per source IP
# -----------------------------

# Clear old rate limit rules if they exist
iptables -D INPUT -m recent --name RATE_LIMIT --update --seconds 60 --hitcount $MAX_CONNECTIONS_PER_MINUTE -j DROP 2>/dev/null || true
iptables -D INPUT -m recent --name RATE_LIMIT --set -j ACCEPT 2>/dev/null || true
iptables -D INPUT -m recent --name RATE_LIMIT --rcheck --seconds 60 --hitcount $MAX_CONNECTIONS_PER_MINUTE -j LOG --log-prefix "RATE-LIMITED: " 2>/dev/null || true

# Apply to specific ports or all
if [ -n "$PROTECTED_PORTS" ]; then
    PORTS_MATCH="-m multiport --dports $PROTECTED_PORTS"
else
    PORTS_MATCH=""
fi

# Log rate-limited connections
iptables -A INPUT -p tcp $PORTS_MATCH -m conntrack --ctstate NEW \
    -m recent --name RATE_LIMIT --rcheck --seconds 60 --hitcount $MAX_CONNECTIONS_PER_MINUTE \
    -j LOG --log-prefix "RATE-LIMITED: " --log-level 4

# Drop connections exceeding rate limit
iptables -A INPUT -p tcp $PORTS_MATCH -m conntrack --ctstate NEW \
    -m recent --name RATE_LIMIT --update --seconds 60 --hitcount $MAX_CONNECTIONS_PER_MINUTE \
    -j DROP

# Track new connections
iptables -A INPUT -p tcp $PORTS_MATCH -m conntrack --ctstate NEW \
    -m recent --name RATE_LIMIT --set

echo "✓ Recent module rate limiting applied"

# -----------------------------
# Method 2: Connlimit - limit concurrent connections
# -----------------------------

# Remove old rules
iptables -D INPUT -p tcp -m connlimit --connlimit-above 50 --connlimit-mask 32 -j DROP 2>/dev/null || true
iptables -D INPUT -p tcp -m connlimit --connlimit-above 50 --connlimit-mask 32 -j LOG --log-prefix "CONNLIMIT: " 2>/dev/null || true

# Log excessive concurrent connections
iptables -A INPUT -p tcp $PORTS_MATCH -m connlimit --connlimit-above 50 --connlimit-mask 32 \
    -j LOG --log-prefix "CONNLIMIT: " --log-level 4

# Drop excessive concurrent connections from single IP
iptables -A INPUT -p tcp $PORTS_MATCH -m connlimit --connlimit-above 50 --connlimit-mask 32 -j DROP

echo "✓ Connection limit (50 concurrent per IP) applied"

# -----------------------------
# Method 3: Hashlimit - more sophisticated rate limiting
# -----------------------------

# Remove old hashlimit rules
iptables -D INPUT -p tcp $PORTS_MATCH -m conntrack --ctstate NEW -m hashlimit \
    --hashlimit-above 30/min --hashlimit-mode srcip --hashlimit-name http_limit -j DROP 2>/dev/null || true

# Apply hashlimit (30 new connections per minute per source IP)
iptables -A INPUT -p tcp $PORTS_MATCH -m conntrack --ctstate NEW \
    -m hashlimit --hashlimit-above 30/min --hashlimit-mode srcip \
    --hashlimit-name conn_limit --hashlimit-burst $BURST_LIMIT \
    -j LOG --log-prefix "HASHLIMIT: " --log-level 4

iptables -A INPUT -p tcp $PORTS_MATCH -m conntrack --ctstate NEW \
    -m hashlimit --hashlimit-above 30/min --hashlimit-mode srcip \
    --hashlimit-name conn_limit --hashlimit-burst $BURST_LIMIT \
    -j DROP

echo "✓ Hashlimit rate limiting applied"

# -----------------------------
# Block IPs in rate_limited ipset
# -----------------------------
iptables -C INPUT -m set --match-set rate_limited src -j DROP 2>/dev/null || \
    iptables -A INPUT -m set --match-set rate_limited src -j DROP

echo "✓ rate_limited ipset blocking active"
echo ""
echo "=== Rate Limiting Active ==="
echo ""
echo "Monitor rate-limited connections:"
echo "  sudo dmesg -w | grep -E 'RATE-LIMITED|CONNLIMIT|HASHLIMIT'"
echo ""
echo "View current tracking:"
echo "  cat /proc/net/xt_recent/RATE_LIMIT"
echo ""
echo "Manually add IP to 24h block:"
echo "  sudo ipset add rate_limited 1.2.3.4"
