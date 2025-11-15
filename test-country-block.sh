#!/bin/bash

# Test if country blocking is working

echo "=== Country Block Test ==="
echo ""

# Check if country_block ipset exists
if ! sudo ipset list country_block &>/dev/null; then
    echo "ERROR: country_block ipset doesn't exist. Run update-scanner-block.sh first."
    exit 1
fi

# Get count of blocked IPs
COUNT=$(sudo ipset list country_block | grep -E '^[0-9]' | wc -l)
echo "Country blocklist loaded: $COUNT networks"
echo ""

# Test some known IPs from blocked countries
echo "Testing sample IPs from blocked countries:"
echo ""

# China - Baidu
echo -n "China (Baidu 220.181.38.148): "
if sudo ipset test country_block 220.181.38.148 2>&1 | grep -q "is in set"; then
    echo "✓ BLOCKED"
else
    echo "✗ NOT BLOCKED"
fi

# China - Alibaba
echo -n "China (Alibaba 47.88.62.1): "
if sudo ipset test country_block 47.88.62.1 2>&1 | grep -q "is in set"; then
    echo "✓ BLOCKED"
else
    echo "✗ NOT BLOCKED"
fi

# Russia - Yandex
echo -n "Russia (Yandex 5.255.255.70): "
if sudo ipset test country_block 5.255.255.70 2>&1 | grep -q "is in set"; then
    echo "✓ BLOCKED"
else
    echo "✗ NOT BLOCKED"
fi

# Iran
echo -n "Iran (2.176.0.1): "
if sudo ipset test country_block 2.176.0.1 2>&1 | grep -q "is in set"; then
    echo "✓ BLOCKED"
else
    echo "✗ NOT BLOCKED"
fi

# North Korea
echo -n "North Korea (175.45.176.1): "
if sudo ipset test country_block 175.45.176.1 2>&1 | grep -q "is in set"; then
    echo "✓ BLOCKED"
else
    echo "✗ NOT BLOCKED"
fi

echo ""
echo "Testing IPs that should NOT be blocked:"
echo ""

# US - Google
echo -n "USA (Google 8.8.8.8): "
if sudo ipset test country_block 8.8.8.8 2>&1 | grep -q "is NOT in set"; then
    echo "✓ NOT BLOCKED (correct)"
else
    echo "✗ BLOCKED (error!)"
fi

# Germany - GitHub
echo -n "USA (GitHub 140.82.121.4): "
if sudo ipset test country_block 140.82.121.4 2>&1 | grep -q "is NOT in set"; then
    echo "✓ NOT BLOCKED (correct)"
else
    echo "✗ BLOCKED (error!)"
fi

echo ""
echo "=== Check iptables rules ==="
sudo iptables -L INPUT -n -v | grep -A1 "country_block"

echo ""
echo "=== Live monitoring ==="
echo "To watch blocked connections in real-time, run:"
echo "  sudo dmesg -w | grep 'SCANNER-BLOCKED'"
