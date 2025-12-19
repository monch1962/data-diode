#!/bin/bash

# Default values
CONCURRENCY=${1:-10}
PAYLOAD_SIZE=${2:-1024}
DURATION_MS=${3:-5000}
PORT=${LISTEN_PORT:-8080}

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="load_test_${TIMESTAMP}.log"

echo "=================================================="
echo "🚀 DataDiode Load Test Automation"
echo "=================================================="
echo "Log file: $LOG_FILE"
echo "Config: $CONCURRENCY clients, $PAYLOAD_SIZE bytes, $DURATION_MS ms"
echo "Target: 127.0.0.1:$PORT"
echo "--------------------------------------------------"

# Run the automated load test via mix run
# This ensures the app is started, test runs, and app is stopped
LISTEN_PORT=$PORT mix run bin/automate_load_test.exs $CONCURRENCY $PAYLOAD_SIZE $DURATION_MS 2>&1 | tee "$LOG_FILE"

echo "--------------------------------------------------"
echo "✅ Load test complete. Detailed logs at $LOG_FILE"
echo "=================================================="
