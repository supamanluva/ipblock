#!/bin/bash
set -e

# -----------------------------
# Port Scan Detection & Blocking
# -----------------------------
# Detects port scanning behavior and blocks offenders
# Uses iptables + log analysis
# -----------------------------

# Configuration
SCAN_THRESHOLD=5              # Number of different ports hit before flagging
SCAN_WINDOW=60                # Time window in seconds
# BLOCK_DURATION - now permanent          # Block for 24 hours

echo "=== Port Scan Detection Setup ==="
echo "Threshold: $SCAN_THRESHOLD ports in $SCAN_WINDOW seconds"
echo ""

# Create ipset if not exists
ipset create portscan_blocked hash:net -exist

# -----------------------------
# Method 1: PSD (Port Scan Detection) match extension
# If available, this is the most elegant solution
# -----------------------------
setup_psd() {
    echo "Checking for iptables PSD extension..."
    if iptables -m psd --help 2>&1 | grep -q "psd-weight-threshold"; then
        echo "✓ PSD extension available!"
        
        # Remove old rules
        iptables -D INPUT -m psd --psd-weight-threshold 21 --psd-delay-threshold 300 \
            --psd-lo-ports-weight 3 --psd-hi-ports-weight 1 -j LOG --log-prefix "PORTSCAN: " 2>/dev/null || true
        iptables -D INPUT -m psd --psd-weight-threshold 21 --psd-delay-threshold 300 \
            --psd-lo-ports-weight 3 --psd-hi-ports-weight 1 -j DROP 2>/dev/null || true
        
        # Log port scans
        iptables -A INPUT -m psd --psd-weight-threshold 21 --psd-delay-threshold 300 \
            --psd-lo-ports-weight 3 --psd-hi-ports-weight 1 \
            -j LOG --log-prefix "PORTSCAN: " --log-level 4
        
        # Drop port scan traffic
        iptables -A INPUT -m psd --psd-weight-threshold 21 --psd-delay-threshold 300 \
            --psd-lo-ports-weight 3 --psd-hi-ports-weight 1 -j DROP
        
        echo "✓ PSD protection enabled"
        return 0
    else
        echo "  PSD extension not available, using alternative methods"
        return 1
    fi
}

# -----------------------------
# Method 2: Recent module for port scan detection
# Track unique port hits per source IP
# -----------------------------
setup_recent_portscan() {
    echo "Setting up recent module port scan detection..."
    
    # Skip whitelisted IPs
    iptables -C INPUT -m set --match-set whitelist src -j RETURN 2>/dev/null || true
    
    # Clean up old rules first
    for i in $(seq 1 10); do
        iptables -D INPUT -p tcp -m conntrack --ctstate NEW -m recent --name portscan --rcheck --seconds $SCAN_WINDOW --hitcount $SCAN_THRESHOLD -j LOG --log-prefix "PORTSCAN: " 2>/dev/null || true
        iptables -D INPUT -p tcp -m conntrack --ctstate NEW -m recent --name portscan --update --seconds $SCAN_WINDOW --hitcount $SCAN_THRESHOLD -j DROP 2>/dev/null || true
        iptables -D INPUT -p tcp -m conntrack --ctstate NEW -m recent --name portscan --set 2>/dev/null || true
    done
    
    # Log detected port scans
    iptables -A INPUT -p tcp -m conntrack --ctstate NEW \
        -m recent --name portscan --rcheck --seconds $SCAN_WINDOW --hitcount $SCAN_THRESHOLD \
        -j LOG --log-prefix "PORTSCAN: " --log-level 4
    
    # Drop and continue tracking
    iptables -A INPUT -p tcp -m conntrack --ctstate NEW \
        -m recent --name portscan --update --seconds $SCAN_WINDOW --hitcount $SCAN_THRESHOLD \
        -j DROP
    
    # Track new connections
    iptables -A INPUT -p tcp -m conntrack --ctstate NEW \
        -m recent --name portscan --set
    
    echo "✓ Recent module port scan detection enabled"
}

# -----------------------------
# Method 3: Trap common scan ports (honeypot ports)
# These ports are rarely used legitimately but often scanned
# -----------------------------
setup_honeypot_ports() {
    echo "Setting up honeypot port detection..."
    
    # Common ports that attackers scan but you likely don't use
    # Adjust this list based on your actual services
    HONEYPOT_PORTS="23,135,137,138,139,445,1433,1434,3306,3389,5432,5900,6379,11211,27017"
    
    # Remove old rules
    iptables -D INPUT -p tcp -m multiport --dports $HONEYPOT_PORTS -m conntrack --ctstate NEW \
        -j LOG --log-prefix "HONEYPOT-HIT: " 2>/dev/null || true
    iptables -D INPUT -p tcp -m multiport --dports $HONEYPOT_PORTS -m conntrack --ctstate NEW \
        -j SET --add-set portscan_blocked src 2>/dev/null || true
    iptables -D INPUT -p tcp -m multiport --dports $HONEYPOT_PORTS -m conntrack --ctstate NEW \
        -j DROP 2>/dev/null || true
    
    # Check if SET target is available
    if iptables -j SET --help 2>&1 | grep -q "add-set"; then
        # Log and auto-add to ipset
        iptables -A INPUT -p tcp -m multiport --dports $HONEYPOT_PORTS -m conntrack --ctstate NEW \
            -j LOG --log-prefix "HONEYPOT-HIT: " --log-level 4
        
        iptables -A INPUT -p tcp -m multiport --dports $HONEYPOT_PORTS -m conntrack --ctstate NEW \
            -j SET --add-set portscan_blocked src 
        
        iptables -A INPUT -p tcp -m multiport --dports $HONEYPOT_PORTS -m conntrack --ctstate NEW \
            -j DROP
        
        echo "✓ Honeypot ports with auto-blocking enabled"
    else
        # Fallback: just log and drop
        iptables -A INPUT -p tcp -m multiport --dports $HONEYPOT_PORTS -m conntrack --ctstate NEW \
            -j LOG --log-prefix "HONEYPOT-HIT: " --log-level 4
        
        iptables -A INPUT -p tcp -m multiport --dports $HONEYPOT_PORTS -m conntrack --ctstate NEW \
            -j DROP
        
        echo "✓ Honeypot ports enabled (manual blocking via log analysis)"
    fi
}

# -----------------------------
# Method 4: Detect NULL, XMAS, and FIN scans
# These are common stealth scanning techniques
# -----------------------------
setup_stealth_scan_detection() {
    echo "Setting up stealth scan detection..."
    
    # Remove old rules
    iptables -D INPUT -p tcp --tcp-flags ALL NONE -j LOG --log-prefix "NULL-SCAN: " 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags ALL NONE -j DROP 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags ALL ALL -j LOG --log-prefix "XMAS-SCAN: " 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags ALL ALL -j DROP 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j LOG --log-prefix "XMAS-SCAN: " 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags ALL SYN,FIN -j LOG --log-prefix "SYNFIN-SCAN: " 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags ALL SYN,FIN -j DROP 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j LOG --log-prefix "SYNRST-SCAN: " 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j LOG --log-prefix "FINRST-SCAN: " 2>/dev/null || true
    iptables -D INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j DROP 2>/dev/null || true
    
    # NULL scan (no flags set)
    iptables -A INPUT -p tcp --tcp-flags ALL NONE \
        -j LOG --log-prefix "NULL-SCAN: " --log-level 4
    iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
    
    # XMAS scan (all flags set)
    iptables -A INPUT -p tcp --tcp-flags ALL ALL \
        -j LOG --log-prefix "XMAS-SCAN: " --log-level 4
    iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
    
    # XMAS scan variant (FIN, PSH, URG)
    iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG \
        -j LOG --log-prefix "XMAS-SCAN: " --log-level 4
    iptables -A INPUT -p tcp --tcp-flags ALL FIN,PSH,URG -j DROP
    
    # SYN/FIN scan (invalid combination)
    iptables -A INPUT -p tcp --tcp-flags ALL SYN,FIN \
        -j LOG --log-prefix "SYNFIN-SCAN: " --log-level 4
    iptables -A INPUT -p tcp --tcp-flags ALL SYN,FIN -j DROP
    
    # SYN/RST scan (invalid combination)
    iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST \
        -j LOG --log-prefix "SYNRST-SCAN: " --log-level 4
    iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
    
    # FIN/RST scan (invalid combination)
    iptables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST \
        -j LOG --log-prefix "FINRST-SCAN: " --log-level 4
    iptables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST -j DROP
    
    echo "✓ Stealth scan detection enabled"
}

# -----------------------------
# Method 5: Block IPs in portscan_blocked ipset
# -----------------------------
setup_ipset_blocking() {
    echo "Setting up ipset blocking for port scanners..."
    
    iptables -C INPUT -m set --match-set portscan_blocked src -j LOG --log-prefix "PORTSCAN-BLOCKED: " 2>/dev/null || \
        iptables -I INPUT 4 -m set --match-set portscan_blocked src -j LOG --log-prefix "PORTSCAN-BLOCKED: " --log-level 4
    
    iptables -C INPUT -m set --match-set portscan_blocked src -j DROP 2>/dev/null || \
        iptables -I INPUT 5 -m set --match-set portscan_blocked src -j DROP
    
    echo "✓ ipset blocking enabled"
}

# -----------------------------
# Run all setup functions
# -----------------------------
setup_psd || setup_recent_portscan
setup_honeypot_ports
setup_stealth_scan_detection
setup_ipset_blocking

echo ""
echo "=== Port Scan Detection Active ==="
echo ""
echo "Monitor detected scans:"
echo "  sudo dmesg -w | grep -E 'PORTSCAN|HONEYPOT|SCAN'"
echo ""
echo "View blocked scanners:"
echo "  sudo ipset list portscan_blocked"
echo ""
echo "Manually block a scanner:"
echo "  sudo ipset add portscan_blocked 1.2.3.4"
echo ""
echo "View recent module tracking:"
echo "  cat /proc/net/xt_recent/portscan"
