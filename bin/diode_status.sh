#!/bin/bash

# data_diode Live Status CLI
# Uses RPC to fetch real-time metrics from the running Elixir node.

# Ensure we are in the right directory if running from release
RELEASE_DIR=${RELEASE_DIR:-"."}
DIODE_BIN="$RELEASE_DIR/bin/data_diode"

BOLD='\033[1m'
GREEN='\033[0;32m'
NC='\033[0m'

if [ ! -f "$DIODE_BIN" ]; then
    # Fallback for dev environment
    echo "Release binary not found at $DIODE_BIN. Attempting to use 'mix' for RPC..."
    STATS=$(mix run -e 'IO.inspect(DataDiode.Metrics.get_stats())' || echo "FAIL")
else
    STATS=$($DIODE_BIN rpc "IO.inspect(DataDiode.Metrics.get_stats())" || echo "FAIL")
fi

if [ "$STATS" == "FAIL" ]; then
    echo "Error: Could not connect to the running Data Diode node."
    exit 1
fi

echo -e "${BOLD}--- Data Diode Live Status ---${NC}"
echo "$STATS" | sed 's/[%{}]//g' | tr ',' '\n' | sed 's/"//g' | awk -F': ' '{printf "%-25s: %s\n", $1, $2}'
echo -e "${BOLD}------------------------------${NC}"
