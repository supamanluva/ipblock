#!/bin/bash
set -e

# -----------------------------
# Master Setup Script
# -----------------------------
# Sets up complete IP blocking protection:
# 1. Prerequisites check
# 2. Scanner/country blocklists
# 3. Port scan detection
# 4. Rate limiting (iptables + log-based)
# 5. fail2ban integration
# 6. Persistence across reboots
# -----------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     IP Block Complete Setup                    ║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║  Scanner blocklists + Port scan detection      ║${NC}"
echo -e "${BLUE}║  Rate limiting + fail2ban integration          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""

# -----------------------------
# Check root
# -----------------------------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: Please run as root (sudo $0)${NC}"
    exit 1
fi

# -----------------------------
# Step 1: Install Prerequisites
# -----------------------------
echo -e "${YELLOW}[1/7] Checking prerequisites...${NC}"

install_if_missing() {
    if ! command -v "$1" &>/dev/null; then
        echo "  Installing $1..."
        apt-get update -qq
        apt-get install -y -qq "$2"
    else
        echo -e "  ${GREEN}✓${NC} $1 installed"
    fi
}

install_if_missing ipset ipset
install_if_missing iptables iptables
install_if_missing curl curl

# Install persistence packages
echo "  Installing persistence packages..."
apt-get install -y -qq iptables-persistent ipset-persistent 2>/dev/null || true

# -----------------------------
# Step 2: Scanner Blocklists
# -----------------------------
echo ""
echo -e "${YELLOW}[2/7] Setting up scanner blocklists...${NC}"

if [ -f "$SCRIPT_DIR/update-scanner-block.sh" ]; then
    bash "$SCRIPT_DIR/update-scanner-block.sh"
    echo -e "  ${GREEN}✓${NC} Scanner blocklists loaded"
else
    echo -e "  ${RED}✗${NC} update-scanner-block.sh not found!"
    exit 1
fi

# -----------------------------
# Step 3: Port Scan Detection
# -----------------------------
echo ""
echo -e "${YELLOW}[3/7] Setting up port scan detection...${NC}"

if [ -f "$SCRIPT_DIR/portscan-detect.sh" ]; then
    bash "$SCRIPT_DIR/portscan-detect.sh"
    echo -e "  ${GREEN}✓${NC} Port scan detection active"
else
    echo -e "  ${YELLOW}⚠${NC} portscan-detect.sh not found, skipping"
fi

# -----------------------------
# Step 4: iptables Rate Limiting
# -----------------------------
echo ""
echo -e "${YELLOW}[4/7] Setting up iptables rate limiting...${NC}"

if [ -f "$SCRIPT_DIR/rate-limit-iptables.sh" ]; then
    bash "$SCRIPT_DIR/rate-limit-iptables.sh"
    echo -e "  ${GREEN}✓${NC} iptables rate limiting active"
else
    echo -e "  ${YELLOW}⚠${NC} rate-limit-iptables.sh not found, skipping"
fi

# -----------------------------
# Step 5: Docker Port Filtering
# -----------------------------
echo ""
echo -e "${YELLOW}[5/8] Setting up Docker port filtering...${NC}"

if [ -f "$SCRIPT_DIR/docker-port-filter.sh" ]; then
    bash "$SCRIPT_DIR/docker-port-filter.sh"
    echo -e "  ${GREEN}✓${NC} Docker port filtering active"
else
    echo -e "  ${YELLOW}⚠${NC} docker-port-filter.sh not found, skipping"
fi

# -----------------------------
# Step 6: Log-Based Rate Limiter
# -----------------------------
echo ""
echo -e "${YELLOW}[6/8] Setting up log-based rate limiter...${NC}"

# Create state directory
mkdir -p /var/lib/ipblock
chmod 700 /var/lib/ipblock

# Create ipsets for dynamic blocking
ipset create rate_limited hash:net timeout 86400 -exist
ipset create fail2ban hash:net timeout 86400 -exist

if [ -f "$SCRIPT_DIR/log-rate-limiter.sh" ]; then
    # Copy script to system location
    cp "$SCRIPT_DIR/log-rate-limiter.sh" /usr/local/bin/log-rate-limiter
    chmod +x /usr/local/bin/log-rate-limiter
    
    # Add cron job (every 5 minutes)
    CRON_JOB="*/5 * * * * root /usr/local/bin/log-rate-limiter >> /var/log/rate-limiter.log 2>&1"
    CRON_FILE="/etc/cron.d/log-rate-limiter"
    echo "$CRON_JOB" > "$CRON_FILE"
    chmod 644 "$CRON_FILE"
    
    echo -e "  ${GREEN}✓${NC} Log rate limiter installed"
    echo -e "  ${GREEN}✓${NC} Cron job created (runs every 5 minutes)"
else
    echo -e "  ${YELLOW}⚠${NC} log-rate-limiter.sh not found, skipping"
fi

# -----------------------------
# Step 7: fail2ban (Optional)
# -----------------------------
echo ""
echo -e "${YELLOW}[7/8] fail2ban setup...${NC}"

if [ -f "$SCRIPT_DIR/fail2ban-setup.sh" ]; then
    read -p "  Install and configure fail2ban? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        bash "$SCRIPT_DIR/fail2ban-setup.sh"
        echo -e "  ${GREEN}✓${NC} fail2ban configured"
    else
        echo -e "  ${YELLOW}⚠${NC} Skipped. Run fail2ban-setup.sh manually later."
    fi
else
    echo -e "  ${YELLOW}⚠${NC} fail2ban-setup.sh not found, skipping"
fi

# -----------------------------
# Step 8: Install to System Path
# -----------------------------
echo ""
echo -e "${YELLOW}[8/8] Installing scripts to system path...${NC}"

# Main blocklist updater
cp "$SCRIPT_DIR/update-scanner-block.sh" /usr/local/bin/update-scanner-blocklist
chmod +x /usr/local/bin/update-scanner-blocklist
echo -e "  ${GREEN}✓${NC} update-scanner-blocklist → /usr/local/bin/"

# Docker port filter
if [ -f "$SCRIPT_DIR/docker-port-filter.sh" ]; then
    cp "$SCRIPT_DIR/docker-port-filter.sh" /usr/local/bin/docker-port-filter
    chmod +x /usr/local/bin/docker-port-filter
    echo -e "  ${GREEN}✓${NC} docker-port-filter → /usr/local/bin/"
fi

# Show blocked utility
if [ -f "$SCRIPT_DIR/show-blocked.sh" ]; then
    cp "$SCRIPT_DIR/show-blocked.sh" /usr/local/bin/show-blocked
    chmod +x /usr/local/bin/show-blocked
    echo -e "  ${GREEN}✓${NC} show-blocked → /usr/local/bin/"
fi

# Verify setup utility
if [ -f "$SCRIPT_DIR/verify-setup.sh" ]; then
    cp "$SCRIPT_DIR/verify-setup.sh" /usr/local/bin/verify-ipblock
    chmod +x /usr/local/bin/verify-ipblock
    echo -e "  ${GREEN}✓${NC} verify-ipblock → /usr/local/bin/"
fi

# -----------------------------
# Save Rules for Persistence
# -----------------------------
echo ""
echo -e "${YELLOW}Saving rules for persistence...${NC}"

# Save ipset
mkdir -p /etc/ipblock
ipset save > /etc/ipblock/ipset.rules 2>/dev/null || true

# Save iptables
netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

# Create persistence cron job
cat > /etc/cron.d/ipblock-persist << EOF
# Save ipsets hourly and restore on reboot
0 * * * * root ipset save > /etc/ipblock/ipset.rules 2>/dev/null
@reboot root sleep 30 && ipset restore < /etc/ipblock/ipset.rules 2>/dev/null && $SCRIPT_DIR/portscan-detect.sh >> /var/log/portscan.log 2>&1
EOF
chmod 644 /etc/cron.d/ipblock-persist

echo -e "  ${GREEN}✓${NC} Rules saved"
echo -e "  ${GREEN}✓${NC} Persistence cron job created"

# -----------------------------
# Setup Cron for Daily Updates
# -----------------------------
echo ""
echo -e "${YELLOW}Setting up daily blocklist updates...${NC}"

DAILY_CRON="0 2 * * * root /usr/local/bin/update-scanner-blocklist >> /var/log/scanner-block.log 2>&1"
DAILY_CRON_FILE="/etc/cron.d/scanner-blocklist-update"
echo "$DAILY_CRON" > "$DAILY_CRON_FILE"
chmod 644 "$DAILY_CRON_FILE"

echo -e "  ${GREEN}✓${NC} Daily cron job created (02:00 every day)"

# -----------------------------
# Summary
# -----------------------------
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Setup Complete!                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo "Protection layers installed:"
echo -e "  ${GREEN}✓${NC} Scanner blocklists (FireHOL Level 1-3)"
echo -e "  ${GREEN}✓${NC} Port scan detection (honeypot + stealth)"
echo -e "  ${GREEN}✓${NC} iptables rate limiting (kernel-level)"
echo -e "  ${GREEN}✓${NC} Log-based rate limiter (cron, 3-strike system)"
if command -v fail2ban-client &>/dev/null && systemctl is-active --quiet fail2ban 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} fail2ban (SSH, HTTP protection)"
else
    echo -e "  ${YELLOW}○${NC} fail2ban (not installed)"
fi
echo ""
echo "Useful commands:"
echo "  sudo show-blocked              # View all blocked IPs"
echo "  sudo verify-ipblock            # Verify setup status"
echo "  sudo update-scanner-blocklist  # Manually update blocklists"
echo ""
echo "Logs:"
echo "  /var/log/scanner-block.log     # Blocklist updates"
echo "  /var/log/rate-limiter.log      # Rate limiter activity"
echo "  /var/log/portscan.log          # Port scan detections"
echo "  sudo dmesg | grep BLOCKED      # Kernel block logs"
echo ""
echo -e "${YELLOW}Tip:${NC} Run 'sudo verify-ipblock' to check everything is working."
