#!/bin/bash
set -e

# -----------------------------
# fail2ban Setup for ipset Integration
# -----------------------------
# Installs and configures fail2ban to work with your ipset system
# Uses ipset for efficient blocking with 24-hour timeout
# -----------------------------

echo "=== fail2ban Setup with ipset Integration ==="
echo ""

# Check if fail2ban is installed
if ! command -v fail2ban-client &> /dev/null; then
    echo "fail2ban not found. Installing..."
    if command -v apt &> /dev/null; then
        apt update && apt install -y fail2ban
    elif command -v yum &> /dev/null; then
        yum install -y fail2ban
    elif command -v dnf &> /dev/null; then
        dnf install -y fail2ban
    elif command -v pacman &> /dev/null; then
        pacman -S --noconfirm fail2ban
    else
        echo "ERROR: Could not detect package manager. Install fail2ban manually."
        exit 1
    fi
fi

echo "✓ fail2ban installed"

# Create ipset for fail2ban
ipset create fail2ban hash:net timeout 86400 -exist
echo "✓ fail2ban ipset created"

# Create custom ipset action
cat > /etc/fail2ban/action.d/ipset-blocklist.conf << 'EOF'
# fail2ban action to add IPs to ipset with timeout
# Uses your existing ipset infrastructure

[Definition]
actionstart = ipset create <ipsetname> hash:net timeout <timeout> -exist
actionstop = 
actioncheck = 
actionban = ipset add <ipsetname> <ip> timeout <timeout> -exist
              logger -t fail2ban "BANNED <ip> for <timeout>s via <name> - <bancount> offenses"
actionunban = ipset del <ipsetname> <ip> -exist
              logger -t fail2ban "UNBANNED <ip> via <name>"

[Init]
ipsetname = fail2ban
timeout = 86400
EOF

echo "✓ Created ipset action"

# Create local jail configuration
cat > /etc/fail2ban/jail.local << 'EOF'
# fail2ban local configuration
# Integrated with ipset blocking system

[DEFAULT]
# Ban for 24 hours
bantime = 86400

# Find time window (10 minutes)
findtime = 600

# Max retries before ban
maxretry = 5

# Use ipset action
banaction = ipset-blocklist[ipsetname=fail2ban, timeout=86400]

# Ignore local networks (adjust to match your whitelist)
ignoreip = 127.0.0.1/8 ::1 10.8.0.0/16 192.168.50.0/24

# Email notifications (optional - configure if wanted)
# destemail = your@email.com
# sender = fail2ban@yourdomain.com
# action = %(action_mwl)s

# -----------------------------
# SSH Protection
# -----------------------------
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
findtime = 600

# Aggressive SSH - for repeated offenders
[sshd-aggressive]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 1
bantime = 604800
findtime = 86400

# -----------------------------
# Web Server Protection
# -----------------------------
# Note: These jails auto-detect based on log file presence

[nginx-http-auth]
enabled = false
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 86400

[nginx-botsearch]
enabled = false
filter = nginx-botsearch
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 86400

[nginx-limit-req]
enabled = false
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 5
findtime = 60
bantime = 86400

# Apache jails
[apache-auth]
enabled = false
filter = apache-auth
logpath = /var/log/apache2/error.log
maxretry = 3

[apache-badbots]
enabled = false
filter = apache-badbots
logpath = /var/log/apache2/access.log
maxretry = 2

# -----------------------------
# Custom: Hammering Detection
# -----------------------------
[http-hammer]
enabled = false
filter = http-hammer
logpath = /var/log/nginx/access.log
          /var/log/apache2/access.log
maxretry = 100
findtime = 60
bantime = 86400

[http-scanner]
enabled = false
filter = http-scanner
logpath = /var/log/nginx/access.log
          /var/log/apache2/access.log
maxretry = 5
findtime = 300
bantime = 86400

# -----------------------------
# Generic Service Protection  
# -----------------------------
[recidive]
# Ban repeat offenders for a week
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
bantime = 604800
findtime = 86400
maxretry = 3

EOF

echo "✓ Created jail.local configuration"

# Auto-enable jails based on installed services
echo "Detecting installed services..."

# Enable nginx jails if nginx is installed and logs exist
if [ -d /var/log/nginx ]; then
    echo "  Enabling nginx jails..."
    sed -i '/^\[nginx-http-auth\]/,/^\[/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
    sed -i '/^\[nginx-botsearch\]/,/^\[/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
    sed -i '/^\[nginx-limit-req\]/,/^\[/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
    # Enable http-hammer and http-scanner with nginx logs
    sed -i '/^\[http-hammer\]/,/^\[/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
    sed -i '/^\[http-scanner\]/,/^\[/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
    echo "  ✓ nginx jails enabled"
fi

# Enable apache jails if apache is installed and logs exist
if [ -d /var/log/apache2 ]; then
    echo "  Enabling apache jails..."
    sed -i '/^\[apache-auth\]/,/^\[/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
    sed -i '/^\[apache-badbots\]/,/^\[/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
    # Update http-hammer and http-scanner to use apache logs if nginx not present
    if [ ! -d /var/log/nginx ]; then
        sed -i '/^\[http-hammer\]/,/^\[/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
        sed -i '/^\[http-hammer\]/,/^\[/ s|/var/log/nginx/access.log|/var/log/apache2/access.log|' /etc/fail2ban/jail.local
        sed -i '/^\[http-scanner\]/,/^\[/ s/enabled = false/enabled = true/' /etc/fail2ban/jail.local
        sed -i '/^\[http-scanner\]/,/^\[/ s|/var/log/nginx/access.log|/var/log/apache2/access.log|' /etc/fail2ban/jail.local
    fi
    echo "  ✓ apache jails enabled"
fi

if [ ! -d /var/log/nginx ] && [ ! -d /var/log/apache2 ]; then
    echo "  ℹ No web server logs found - HTTP jails disabled"
fi

# Create custom filters
mkdir -p /etc/fail2ban/filter.d

# HTTP Hammering filter
cat > /etc/fail2ban/filter.d/http-hammer.conf << 'EOF'
# Detect HTTP request hammering (too many requests too fast)
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|OPTIONS).*HTTP.*"
ignoreregex =
datepattern = %%d/%%b/%%Y:%%H:%%M:%%S
EOF

# HTTP Scanner filter (suspicious paths)
cat > /etc/fail2ban/filter.d/http-scanner.conf << 'EOF'
# Detect vulnerability scanning and suspicious path access
[Definition]
failregex = ^<HOST> -.*"(GET|POST).*(\.php|\.asp|\.env|\.git|wp-admin|wp-login|phpmyadmin|admin|config|backup|shell|eval|passwd|\.sql|\.bak|\.zip|\.tar|xmlrpc).*" (400|401|403|404|405|500)
            ^<HOST> -.*"(GET|POST).*(\.\.\/|%%2e%%2e|%%00|union.*select|<script|javascript:|data:).*"
ignoreregex =
datepattern = %%d/%%b/%%Y:%%H:%%M:%%S
EOF

# Nginx botsearch filter (updated)
cat > /etc/fail2ban/filter.d/nginx-botsearch.conf << 'EOF'
# Detect bot scanning behavior
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*" 404
            ^<HOST> -.*"(GET|POST).*robots\.txt.*"
ignoreregex = 
datepattern = %%d/%%b/%%Y:%%H:%%M:%%S
EOF

echo "✓ Created custom filters"

# Add iptables rule for fail2ban ipset
iptables -C INPUT -m set --match-set fail2ban src -j DROP 2>/dev/null || \
    iptables -A INPUT -m set --match-set fail2ban src -j DROP

echo "✓ Added iptables rule for fail2ban ipset"

# Restart fail2ban
systemctl enable fail2ban

# Stop first if running (ignore errors)
systemctl stop fail2ban 2>/dev/null || true
sleep 1

# Start fresh
systemctl start fail2ban

# Wait for fail2ban to be ready
echo "Waiting for fail2ban to start..."
for i in {1..10}; do
    if fail2ban-client ping &>/dev/null; then
        break
    fi
    sleep 1
done

echo ""
echo "=== fail2ban Setup Complete ==="
echo ""
echo "Status:"
if fail2ban-client ping &>/dev/null; then
    fail2ban-client status
else
    echo "fail2ban is starting up... check status with: fail2ban-client status"
fi

echo ""
echo "Useful commands:"
echo "  fail2ban-client status              # Show all jail status"
echo "  fail2ban-client status sshd         # Show specific jail"
echo "  fail2ban-client set sshd banip IP   # Manually ban IP"
echo "  fail2ban-client set sshd unbanip IP # Manually unban IP"
echo "  fail2ban-client reload              # Reload configuration"
echo ""
echo "View bans:"
echo "  ipset list fail2ban"
echo ""
echo "Logs:"
echo "  tail -f /var/log/fail2ban.log"
