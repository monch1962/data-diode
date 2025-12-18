#!/bin/bash

# data_diode Diagnostic Health Check
# Version 1.0.0

set -e

# Default ports (can be overridden by environment variables)
S1_PORT=${LISTEN_PORT:-8080}
S2_PORT=${LISTEN_PORT_S2:-42001}

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${BOLD}--- Data Diode Health Check ---${NC}"

# 1. Check if process is running
PID=$(pgrep -f "data_diode" || true)
if [ -n "$PID" ]; then
    echo -e "[${GREEN}OK${NC}] Data Diode process is running (PID: $PID)"
else
    echo -e "[${RED}FAIL${NC}] Data Diode process NOT found"
fi

# 2. Check Port Bindings
echo -e "\n${BOLD}Checking Network Ports:${NC}"

# Check S1 TCP
if command -v ss > /dev/null; then
    S1_CHECK=$(ss -tln | grep ":$S1_PORT " || true)
else
    S1_CHECK=$(netstat -an | grep "LISTEN" | grep ":$S1_PORT " || true)
fi

if [ -n "$S1_CHECK" ]; then
    echo -e "[${GREEN}OK${NC}] S1 is listening on TCP port $S1_PORT"
else
    echo -e "[${RED}FAIL${NC}] S1 is NOT listening on TCP port $S1_PORT"
fi

# Check S2 UDP
if command -v ss > /dev/null; then
    S2_CHECK=$(ss -uln | grep ":$S2_PORT " || true)
else
    S2_CHECK=$(netstat -an | grep "UDP" | grep ":$S2_PORT " || true)
fi

if [ -n "$S2_CHECK" ]; then
    echo -e "[${GREEN}OK${NC}] S2 is listening on UDP port $S2_PORT"
else
    echo -e "[${RED}FAIL${NC}] S2 is NOT listening on UDP port $S2_PORT"
fi

# 3. Log Inspection
echo -e "\n${BOLD}Inspecting Logs (Last 10 Errors):${NC}"
# Attempting to find logs in common locations
LOG_LOCATIONS=("_build/prod/rel/data_diode/tmp/log/erlang.log.1" "stdout")

FOUND_ERRORS=0
# If running via systemd, use journalctl
if command -v journalctl > /dev/null && systemctl is-active --quiet data_diode 2>/dev/null; then
    ERRORS=$(journalctl -u data_diode -n 100 --no-pager | grep -iE "error|fatal|exception" | tail -n 10 || true)
    if [ -n "$ERRORS" ]; then
        echo -e "${YELLOW}$ERRORS${NC}"
        FOUND_ERRORS=1
    fi
fi

if [ $FOUND_ERRORS -eq 0 ]; then
    echo "No recent critical errors found in system logs."
fi

# 4. System Resources
echo -e "\n${BOLD}System Resources:${NC}"
df -h / | tail -n 1 | awk '{print "Disk Usage (SD Card): " $5 " used (" $4 " available)"}'
free -m | grep "Mem" | awk '{print "Memory Usage: " $3 "MB used / " $2 "MB total"}'

echo -e "\n${BOLD}--- Check Complete ---${NC}"
