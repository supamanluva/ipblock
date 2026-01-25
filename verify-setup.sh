#!/bin/bash
#
# verify-setup.sh - Verify IP blocking setup is complete and working
#
# Run after setup to ensure everything is configured correctly.
# Usage: sudo ./verify-setup.sh
#

set +e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

pass() { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; ((WARN++)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }
section() { echo ""; echo -e "${BLUE}═══ $1 ═══${NC}"; }

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     IP Block Setup Verification                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"

section "Required Tools"

for cmd in ipset iptables curl; do
    if command -v $cmd &>/dev/null; then
        pass "$cmd installed"
    else
        fail "$cmd not found - please install it"
    fi
done

for cmd in fail2ban-client conntrack; do
    if command -v $cmd &>/dev/null; then
        pass "$cmd installed (optional)"
    else
        warn "$cmd not installed (optional)"
    fi
done

section "ipset Tables"

for ipset_name in scanners whitelist; do
    if ipset list "$ipset_name" &>/dev/null; then
        count=$(ipset list "$ipset_name" 2>/dev/null | grep -c "^[0-9]" 2>/dev/null || true)
        count=${count:-0}
        pass "$ipset_name exists ($count entries)"
    else
        fail "$ipset_name not found - run update-scanner-block.sh"
    fi
done

if ipset list portscan_blocked &>/dev/null; then
    count=$(ipset list portscan_blocked 2>/dev/null | grep -c "^[0-9]" 2>/dev/null || true)
    count=${count:-0}
    if ipset list portscan_blocked 2>/dev/null | head -5 | grep -q "timeout"; then
        warn "portscan_blocked has timeout (should be permanent)"
    else
        pass "portscan_blocked exists - permanent ($count entries)"
    fi
else
    warn "portscan_blocked not found - run portscan-detect.sh"
fi

if ipset list country_block &>/dev/null; then
    count=$(ipset list country_block 2>/dev/null | grep -c "^[0-9]" 2>/dev/null || true)
    count=${count:-0}
    pass "country_block exists ($count entries)"
else
    info "country_block not found (optional)"
fi

for ipset_name in rate_limited fail2ban; do
    if ipset list "$ipset_name" &>/dev/null; then
        count=$(ipset list "$ipset_name" 2>/dev/null | grep -c "^[0-9]" 2>/dev/null || true)
        count=${count:-0}
        pass "$ipset_name exists ($count entries)"
    else
        info "$ipset_name not found (optional)"
    fi
done

section "iptables Rules"

if iptables -L INPUT -n 2>/dev/null | grep -q "match-set scanners"; then
    pass "Scanner blocking rule active"
else
    fail "Scanner blocking rule not found"
fi

if iptables -L INPUT -n 2>/dev/null | grep -q "match-set whitelist"; then
    pass "Whitelist rule active"
else
    warn "Whitelist rule not found"
fi

if iptables -L INPUT -n 2>/dev/null | grep -q "match-set portscan_blocked"; then
    pass "Port scan blocking rule active"
else
    warn "Port scan blocking rule not found"
fi

if iptables -L INPUT -n 2>/dev/null | grep -qE "dpt:(23|3389|5900)"; then
    pass "Honeypot port rules active"
else
    warn "Honeypot port rules not found"
fi

if iptables -L INPUT -n 2>/dev/null | grep -qE "hashlimit|recent|connlimit"; then
    pass "Rate limiting rules active"
else
    info "Rate limiting rules not found (optional)"
fi

if iptables -L INPUT -n 2>/dev/null | grep -q "match-set country_block"; then
    pass "Country blocking rule active"
else
    info "Country blocking not active (optional)"
fi

section "Services"

if command -v fail2ban-client &>/dev/null; then
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        jails=$(fail2ban-client status 2>/dev/null | grep "Jail list" | sed 's/.*:\s*//' | tr -d '\t')
        pass "fail2ban running (jails: $jails)"
    else
        warn "fail2ban installed but not running"
    fi
fi

section "Cron Jobs & Persistence"

if [[ -f /etc/cron.d/ipblock-persist ]]; then
    pass "ipblock-persist cron job exists"
    if grep -q "@reboot" /etc/cron.d/ipblock-persist; then
        pass "Reboot restore configured"
    else
        warn "Reboot restore not configured"
    fi
else
    warn "ipblock-persist cron not found - blocks won't survive reboot"
fi

if [[ -d /etc/ipblock ]]; then
    pass "/etc/ipblock directory exists"
    if [[ -f /etc/ipblock/portscan_blocked.save ]]; then
        entries=$(grep -c "^add" /etc/ipblock/portscan_blocked.save 2>/dev/null || echo "0")
        pass "portscan_blocked.save exists ($entries saved)"
    else
        info "No saved port scan blocks yet"
    fi
else
    warn "/etc/ipblock not found - create with: mkdir -p /etc/ipblock"
fi

section "Recent Activity"

recent_blocks=$(dmesg 2>/dev/null | grep -cE 'SCANNER-BLOCK|PORTSCAN|HONEYPOT|STEALTH|RATE-LIMITED' || echo "0")
if [[ $recent_blocks -gt 0 ]]; then
    pass "Blocking is active ($recent_blocks events in kernel log)"
    echo ""
    echo -e "  ${BLUE}Last 3 block events:${NC}"
    dmesg 2>/dev/null | grep -E 'SCANNER-BLOCK|PORTSCAN|HONEYPOT|STEALTH|RATE-LIMITED' | tail -3 | while read line; do
        echo -e "    ${YELLOW}→${NC} $(echo "$line" | cut -d']' -f2-)"
    done
else
    info "No recent block events (normal if newly set up)"
fi

section "Quick Stats"

echo ""
total_blocked=0
for ipset_name in scanners country_block portscan_blocked rate_limited fail2ban; do
    if ipset list "$ipset_name" &>/dev/null 2>&1; then
        count=$(ipset list "$ipset_name" 2>/dev/null | grep -c "^[0-9]" 2>/dev/null || true)
        count=${count:-0}
        total_blocked=$((total_blocked + count))
    fi
done
echo -e "  Total IPs/ranges blocked: ${GREEN}$total_blocked${NC}"

if command -v conntrack &>/dev/null; then
    active=$(conntrack -C 2>/dev/null || echo "N/A")
    echo -e "  Active connections: ${GREEN}$active${NC}"
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASS"
echo -e "  ${YELLOW}Warnings:${NC} $WARN"
echo -e "  ${RED}Failed:${NC}  $FAIL"
echo ""

if [[ $FAIL -eq 0 && $WARN -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed! Your IP blocking setup is complete.${NC}"
    exit 0
elif [[ $FAIL -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Setup is functional with some optional features missing.${NC}"
    exit 0
else
    echo -e "${RED}✗ Some required components are missing.${NC}"
    echo ""
    echo -e "  ${BLUE}Quick fix - run these commands:${NC}"
    echo ""
    if ! ipset list scanners &>/dev/null; then
        echo "    sudo ./update-scanner-block.sh"
    fi
    if ! iptables -L INPUT -n 2>/dev/null | grep -q "match-set portscan_blocked"; then
        echo "    sudo ./portscan-detect.sh"
    fi
    if [[ ! -d /etc/ipblock ]]; then
        echo "    sudo mkdir -p /etc/ipblock"
    fi
    echo ""
    exit 1
fi
