#!/bin/bash
set -e

# -----------------------------
# Custom Log-Based Rate Limiter
# -----------------------------
# Parses web server logs to detect hammering IPs
# Adds offenders to ipset with 24-hour timeout
# Run via cron every 5 minutes
# -----------------------------

# Configuration
LOG_FILES=(
    "/var/log/nginx/access.log"
    "/var/log/apache2/access.log"
    "/var/log/httpd/access_log"
)

# Thresholds (adjust based on your traffic patterns)
REQUESTS_PER_MINUTE=60          # Max requests per minute before flagging
REQUESTS_PER_5MIN=200           # Max requests per 5 minutes
BLOCK_DURATION=86400            # Block duration in seconds (24 hours)
ERROR_THRESHOLD=20              # Max 4xx/5xx errors per minute
REPEATED_404_THRESHOLD=10       # Max 404s per minute (scanning behavior)

# State files
STATE_DIR="/var/lib/ipblock"
OFFENDER_LOG="$STATE_DIR/offenders.log"
STRIKE_FILE="$STATE_DIR/strikes.db"

# Create state directory
mkdir -p "$STATE_DIR"
touch "$STRIKE_FILE"

# Create ipset with timeout if not exists
ipset create rate_limited hash:net timeout $BLOCK_DURATION -exist

echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting log analysis..."

# Find which log file exists
LOG_FILE=""
for log in "${LOG_FILES[@]}"; do
    if [ -f "$log" ]; then
        LOG_FILE="$log"
        break
    fi
done

if [ -z "$LOG_FILE" ]; then
    echo "No access log found. Checking dmesg for blocked connections..."
    LOG_FILE="dmesg"
fi

# -----------------------------
# Function: Add strike and possibly block
# -----------------------------
add_strike() {
    local ip="$1"
    local reason="$2"
    local current_time=$(date +%s)
    
    # Skip whitelisted IPs
    if ipset test whitelist "$ip" 2>/dev/null; then
        return 0
    fi
    
    # Get current strikes (within last hour)
    local strikes=$(grep "^$ip " "$STRIKE_FILE" 2>/dev/null | \
        awk -v cutoff=$((current_time - 3600)) '$2 > cutoff {count++} END {print count+0}')
    
    # Add new strike
    echo "$ip $current_time $reason" >> "$STRIKE_FILE"
    strikes=$((strikes + 1))
    
    echo "  Strike $strikes for $ip: $reason"
    
    # Block after 3 strikes
    if [ "$strikes" -ge 3 ]; then
        echo "  >>> BLOCKING $ip for 24 hours (3+ strikes)"
        ipset add rate_limited "$ip" timeout $BLOCK_DURATION -exist
        echo "$(date '+%Y-%m-%d %H:%M:%S') BLOCKED $ip - Reason: $reason (strikes: $strikes)" >> "$OFFENDER_LOG"
    fi
}

# -----------------------------
# Analyze web server logs
# -----------------------------
analyze_web_logs() {
    local log="$1"
    local time_window=300  # 5 minutes
    local cutoff_time=$(date -d "$time_window seconds ago" '+%d/%b/%Y:%H:%M' 2>/dev/null || \
                        date -v-${time_window}S '+%d/%b/%Y:%H:%M' 2>/dev/null)
    
    echo "Analyzing $log..."
    
    # Extract recent entries and count by IP
    # Handles common log format: IP - - [timestamp] "request" status size
    
    # High request rate detection
    echo "Checking for high request rates..."
    tail -10000 "$log" 2>/dev/null | \
        awk '{print $1}' | \
        sort | uniq -c | sort -rn | \
        while read count ip; do
            if [ "$count" -gt "$REQUESTS_PER_5MIN" ]; then
                add_strike "$ip" "High request rate: $count requests in 5 min"
            fi
        done
    
    # 404 scanning detection
    echo "Checking for 404 scanning..."
    tail -5000 "$log" 2>/dev/null | \
        awk '$9 == 404 {print $1}' | \
        sort | uniq -c | sort -rn | \
        while read count ip; do
            if [ "$count" -gt "$REPEATED_404_THRESHOLD" ]; then
                add_strike "$ip" "404 scanning: $count not-found requests"
            fi
        done
    
    # Error rate detection (4xx and 5xx)
    echo "Checking for high error rates..."
    tail -5000 "$log" 2>/dev/null | \
        awk '$9 ~ /^[45][0-9][0-9]$/ {print $1}' | \
        sort | uniq -c | sort -rn | \
        while read count ip; do
            if [ "$count" -gt "$ERROR_THRESHOLD" ]; then
                add_strike "$ip" "High error rate: $count errors"
            fi
        done
    
    # Suspicious path scanning (common attack paths)
    echo "Checking for suspicious path access..."
    tail -5000 "$log" 2>/dev/null | \
        grep -iE '(wp-admin|\.php|/admin|/phpmyadmin|\.env|/config|/backup|\.git|\.sql|/shell|/cmd|eval\(|passwd|/etc/)' | \
        awk '{print $1}' | \
        sort | uniq -c | sort -rn | \
        while read count ip; do
            if [ "$count" -gt 5 ]; then
                add_strike "$ip" "Suspicious path scanning: $count attempts"
            fi
        done
}

# -----------------------------
# Analyze dmesg/kernel logs for blocked attempts
# -----------------------------
analyze_dmesg() {
    echo "Analyzing kernel logs for repeated blocked attempts..."
    
    # Get recent SCANNER-BLOCKED entries
    dmesg --time-format=iso 2>/dev/null | tail -1000 | \
        grep -E 'SCANNER-BLOCKED|RATE-LIMITED' | \
        grep -oE 'SRC=[0-9.]+' | \
        cut -d= -f2 | \
        sort | uniq -c | sort -rn | \
        while read count ip; do
            if [ "$count" -gt 10 ]; then
                add_strike "$ip" "Repeated blocked attempts: $count times"
            fi
        done
}

# -----------------------------
# Analyze auth logs for brute force
# -----------------------------
analyze_auth_logs() {
    local auth_log="/var/log/auth.log"
    [ -f "/var/log/secure" ] && auth_log="/var/log/secure"
    
    if [ -f "$auth_log" ]; then
        echo "Analyzing auth logs for brute force..."
        
        tail -5000 "$auth_log" 2>/dev/null | \
            grep -i "failed\|invalid\|authentication failure" | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
            sort | uniq -c | sort -rn | \
            while read count ip; do
                if [ "$count" -gt 5 ]; then
                    add_strike "$ip" "Auth failures: $count failed attempts"
                fi
            done
    fi
}

# -----------------------------
# Cleanup old strikes
# -----------------------------
cleanup_old_strikes() {
    local current_time=$(date +%s)
    local cutoff=$((current_time - 7200))  # 2 hours
    
    if [ -f "$STRIKE_FILE" ]; then
        awk -v cutoff="$cutoff" '$2 > cutoff' "$STRIKE_FILE" > "${STRIKE_FILE}.tmp"
        mv "${STRIKE_FILE}.tmp" "$STRIKE_FILE"
    fi
}

# -----------------------------
# Main execution
# -----------------------------

cleanup_old_strikes

if [ "$LOG_FILE" = "dmesg" ]; then
    analyze_dmesg
else
    analyze_web_logs "$LOG_FILE"
fi

analyze_auth_logs
analyze_dmesg

# Show current blocks
BLOCKED_COUNT=$(ipset list rate_limited 2>/dev/null | grep -cE '^[0-9]' || echo "0")
echo ""
echo "=== Summary ==="
echo "Currently rate-limited IPs: $BLOCKED_COUNT"
echo "Strike database entries: $(wc -l < "$STRIKE_FILE" 2>/dev/null || echo 0)"
echo ""
echo "Recent blocks:"
tail -5 "$OFFENDER_LOG" 2>/dev/null || echo "  (none yet)"
