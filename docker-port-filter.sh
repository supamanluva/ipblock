#!/bin/bash
set -e

# -----------------------------------------------------
# Docker Port Filter
# -----------------------------------------------------
# Restricts which Docker-published ports are accessible
# from the internet. Only explicitly allowed ports are
# reachable; all others are blocked from external access
# but remain accessible between containers.
#
# This works by adding port-level rules to DOCKER-USER
# BEFORE the final RETURN rule.
# -----------------------------------------------------

# Ports that should be accessible from the internet
# All other Docker-published ports will be blocked from external access
ALLOWED_PORTS="80,443,81"

# Docker bridge network interface (traffic from outside enters via this)
# Use empty string to match all interfaces
DOCKER_IFACE="br-"

# -----------------------------------------------------

echo "Setting up Docker port filtering..."

# Verify DOCKER-USER chain exists
if ! iptables -L DOCKER-USER -n &>/dev/null; then
    echo "WARNING: DOCKER-USER chain not found. Is Docker running?"
    echo "Skipping Docker port filter setup."
    exit 0
fi

# Get the current rule count in DOCKER-USER
RULE_COUNT=$(iptables -L DOCKER-USER --line-numbers -n | tail -n +3 | wc -l)

if [ "$RULE_COUNT" -eq 0 ]; then
    echo "WARNING: DOCKER-USER chain is empty. Run update-scanner-block.sh first."
    exit 1
fi

# Find the position of the final RETURN rule (should be last)
LAST_RULE_NUM=$(iptables -L DOCKER-USER --line-numbers -n | tail -n +3 | tail -1 | awk '{print $1}')
LAST_RULE_TARGET=$(iptables -L DOCKER-USER --line-numbers -n | tail -n +3 | tail -1 | awk '{print $2}')

if [ "$LAST_RULE_TARGET" != "RETURN" ]; then
    echo "WARNING: Last rule in DOCKER-USER is not RETURN. Chain may be misconfigured."
    echo "Last rule: $LAST_RULE_TARGET"
    exit 1
fi

# Remove any existing port filter rules (identified by comment)
while iptables -L DOCKER-USER -n --line-numbers | grep -q "DOCKER-PORT-FILTER"; do
    RULE_NUM=$(iptables -L DOCKER-USER -n --line-numbers | grep "DOCKER-PORT-FILTER" | head -1 | awk '{print $1}')
    iptables -D DOCKER-USER "$RULE_NUM"
done

# Re-check position of final RETURN after cleanup
LAST_RULE_NUM=$(iptables -L DOCKER-USER --line-numbers -n | tail -n +3 | tail -1 | awk '{print $1}')

# Insert private range RETURN rules EARLY in the chain (position 3),
# right after established/whitelist and BEFORE any ipset DROP rules.
# This is critical: scanner blocklists may contain RFC1918 CIDR ranges
# (e.g. 172.16.0.0/12) which would otherwise block container-to-container traffic.

# Find the insertion point: after established + whitelist rules (usually position 3)
PRIVATE_INSERT=3

# Allow all traffic from private networks (container-to-container, localhost)
iptables -I DOCKER-USER "$PRIVATE_INSERT" \
    -s 172.16.0.0/12 \
    -m comment --comment "DOCKER-PORT-FILTER: allow docker internal" \
    -j RETURN

iptables -I DOCKER-USER $((PRIVATE_INSERT + 1)) \
    -s 10.0.0.0/8 \
    -m comment --comment "DOCKER-PORT-FILTER: allow private 10.x" \
    -j RETURN

iptables -I DOCKER-USER $((PRIVATE_INSERT + 2)) \
    -s 192.168.0.0/16 \
    -m comment --comment "DOCKER-PORT-FILTER: allow private 192.168.x" \
    -j RETURN

# Re-check position of final RETURN after inserting private range rules
LAST_RULE_NUM=$(iptables -L DOCKER-USER --line-numbers -n | tail -n +3 | tail -1 | awk '{print $1}')

# Insert port filter rules BEFORE the final RETURN
# Rule: Allow traffic to permitted ports, DROP everything else
# We only filter NEW connections from external (non-private) sources

# Allow traffic to permitted ports (insert before RETURN)
iptables -I DOCKER-USER "$LAST_RULE_NUM" \
    -p tcp -m multiport --dports "$ALLOWED_PORTS" \
    -m conntrack --ctstate NEW \
    -m comment --comment "DOCKER-PORT-FILTER: allow public ports" \
    -j RETURN

# Drop NEW connections to all other TCP ports from external sources
iptables -I DOCKER-USER $((LAST_RULE_NUM + 1)) \
    -p tcp -m conntrack --ctstate NEW \
    -m comment --comment "DOCKER-PORT-FILTER: block other ports" \
    -j DROP

# Also block UDP from external sources
iptables -I DOCKER-USER $((LAST_RULE_NUM + 2)) \
    -p udp -m conntrack --ctstate NEW \
    -m comment --comment "DOCKER-PORT-FILTER: block external UDP" \
    -j DROP

echo "Docker port filtering active."
echo "  Allowed ports from internet: $ALLOWED_PORTS"
echo "  All other Docker ports: blocked from external, accessible internally"
echo ""
echo "Current DOCKER-USER chain:"
iptables -L DOCKER-USER -n --line-numbers | head -20
