#!/bin/bash
set -e

# -----------------------------
# Master Installation Script
# -----------------------------
# Installs all three rate limiting systems:
# 1. iptables rate limiting (immediate, kernel-level)
# 2. Log-based rate limiter (custom script, cron-based)
# 3. fail2ban integration (comprehensive, log-based)
# -----------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "  IP Rate Limiting & Hammering Protection"
echo "=============================================="
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo $0)"
    exit 1
fi

# -----------------------------
# Step 1: Create shared ipsets
# -----------------------------
echo "[1/5] Creating shared ipsets..."

# Ensure whitelist exists (should already from update-scanner-block.sh)
ipset create whitelist hash:net -exist
ipset add whitelist 10.8.0.0/16 -exist
ipset add whitelist 192.168.50.0/24 -exist

# Rate limited IPs (24 hour timeout)
ipset create rate_limited hash:net timeout 86400 -exist

# fail2ban ipset (24 hour timeout)
ipset create fail2ban hash:net timeout 86400 -exist

echo "  ✓ Whitelist ipset ready"
echo "  ✓ rate_limited ipset ready (24h timeout)"
echo "  ✓ fail2ban ipset ready (24h timeout)"

# -----------------------------
# Step 2: Apply iptables rate limiting
# -----------------------------
echo ""
echo "[2/5] Applying iptables rate limiting..."
bash "$SCRIPT_DIR/rate-limit-iptables.sh"

# -----------------------------
# Step 3: Setup log-based rate limiter
# -----------------------------
echo ""
echo "[3/5] Setting up log-based rate limiter..."

# Create state directory
mkdir -p /var/lib/ipblock
chmod 700 /var/lib/ipblock

# Copy script to system location
cp "$SCRIPT_DIR/log-rate-limiter.sh" /usr/local/bin/log-rate-limiter
chmod +x /usr/local/bin/log-rate-limiter

# Add cron job (every 5 minutes)
CRON_JOB="*/5 * * * * root /usr/local/bin/log-rate-limiter >> /var/log/rate-limiter.log 2>&1"
CRON_FILE="/etc/cron.d/log-rate-limiter"

echo "$CRON_JOB" > "$CRON_FILE"
chmod 644 "$CRON_FILE"

echo "  ✓ Log rate limiter installed to /usr/local/bin/log-rate-limiter"
echo "  ✓ Cron job created (runs every 5 minutes)"

# -----------------------------
# Step 4: Setup fail2ban
# -----------------------------
echo ""
echo "[4/5] Setting up fail2ban..."

# Check if user wants fail2ban
read -p "Install and configure fail2ban? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$SCRIPT_DIR/fail2ban-setup.sh"
else
    echo "  Skipping fail2ban setup. Run fail2ban-setup.sh manually later if needed."
fi

# -----------------------------
# Step 5: Add blocking rules for all ipsets
# -----------------------------
echo ""
echo "[5/5] Ensuring all blocking rules are in place..."

# Whitelist first (allow)
iptables -C INPUT -m set --match-set whitelist src -j ACCEPT 2>/dev/null || \
    iptables -I INPUT 3 -m set --match-set whitelist src -j ACCEPT

# Block rate_limited
iptables -C INPUT -m set --match-set rate_limited src -j LOG --log-prefix "RATELIMIT-BLOCKED: " 2>/dev/null || \
    iptables -A INPUT -m set --match-set rate_limited src -j LOG --log-prefix "RATELIMIT-BLOCKED: " --log-level 4

iptables -C INPUT -m set --match-set rate_limited src -j DROP 2>/dev/null || \
    iptables -A INPUT -m set --match-set rate_limited src -j DROP

# Block fail2ban
iptables -C INPUT -m set --match-set fail2ban src -j LOG --log-prefix "FAIL2BAN-BLOCKED: " 2>/dev/null || \
    iptables -A INPUT -m set --match-set fail2ban src -j LOG --log-prefix "FAIL2BAN-BLOCKED: " --log-level 4

iptables -C INPUT -m set --match-set fail2ban src -j DROP 2>/dev/null || \
    iptables -A INPUT -m set --match-set fail2ban src -j DROP

echo "  ✓ All blocking rules active"

# -----------------------------
# Summary
# -----------------------------
echo ""
echo "=============================================="
echo "  Installation Complete!"
echo "=============================================="
echo ""
echo "Active Protection Layers:"
echo ""
echo "  1. iptables Rate Limiting (kernel-level)"
echo "     - Max 30 connections/minute per IP"
echo "     - Max 50 concurrent connections per IP"
echo "     - Burst protection with hashlimit"
echo ""
echo "  2. Log-Based Rate Limiter (cron-based)"
echo "     - Scans logs every 5 minutes"
echo "     - Strike system (3 strikes = 24h ban)"
echo "     - Detects: high request rate, 404 scanning,"
echo "       suspicious paths, auth failures"
echo ""
echo "  3. fail2ban (if installed)"
echo "     - SSH brute force protection"
echo "     - Web server attack protection"
echo "     - Recidive (repeat offender) detection"
echo ""
echo "Monitor commands:"
echo "  sudo dmesg -w | grep -E 'RATE|BLOCKED|LIMIT'"
echo "  sudo tail -f /var/log/rate-limiter.log"
echo "  sudo fail2ban-client status"
echo ""
echo "View blocked IPs:"
echo "  sudo ipset list rate_limited"
echo "  sudo ipset list fail2ban"
echo ""
echo "Manually block an IP for 24h:"
echo "  sudo ipset add rate_limited 1.2.3.4"
echo ""
echo "Unblock an IP:"
echo "  sudo ipset del rate_limited 1.2.3.4"
