#!/bin/bash
#
# deploy-for-harsh-environment.sh
# Deploys the Data Diode for operation in harsh, unattended environments.
#
# Features:
# - Separate data partition configuration
# - Log rotation setup
# - Kernel parameter tuning
# - Environmental sensor setup
# - UPS monitoring configuration
# - Hardware watchdog setup
# - Systemd service installation
#

set -e

echo "========================================"
echo "Data Diode - Harsh Environment Deployment"
echo "========================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Configuration
DEPLOY_DIR="/opt/data-diode"
DATA_DIR="/var/lib/data-diode"
LOG_DIR="/var/log/data-diode"
ALERT_DIR="/var/log/data-diode"
USER="diode"
GROUP="diode"

echo "[1/10] Creating user and directories..."
useradd -r -s /bin/bash -d $DEPLOY_DIR $USER 2>/dev/null || echo "User $USER already exists"
mkdir -p $DEPLOY_DIR
mkdir -p $DATA_DIR
mkdir -p $LOG_DIR
mkdir -p $ALERT_DIR

echo "[2/10] Configuring storage..."
# Check if separate data partition exists
if lsblk -o NAME,MOUNTPOINT | grep -q "^sd.*$DATA_DIR"; then
    echo "Separate data partition already mounted at $DATA_DIR"
else
    # Look for unmounted data partition
    DATA_PART=$(lsblk -o NAME,TYPE,MOUNTPOINT -n | awk '/part/ && !/$DATA_DIR/ {print "/dev/" $1; exit}')

    if [ -n "$DATA_PART" ]; then
        echo "Found data partition: $DATA_PART"

        # Format if needed (commented out for safety - uncomment with caution)
        # mkfs.ext4 -F $DATA_PART

        # Mount with proper options for harsh environments
        mkdir -p $DATA_DIR
        echo "$DATA_PART $DATA_DIR ext4 defaults,noatime,errors=remount-ro 0 2" >> /etc/fstab
        mount $DATA_PART
        echo "Data partition mounted at $DATA_DIR"
    else
        echo "No separate data partition found, using $DATA_DIR on root filesystem"
    fi
fi

echo "[3/10] Setting permissions..."
chown -R $USER:$GROUP $DEPLOY_DIR
chown -R $USER:$GROUP $DATA_DIR
chown -R $USER:$GROUP $LOG_DIR
chmod 755 $DEPLOY_DIR
chmod 775 $DATA_DIR
chmod 775 $LOG_DIR

echo "[4/10] Installing system dependencies..."
apt-get update
apt-get install -y \
    curl \
    git \
    build-essential \
    erlang \
    elixir \
    i2c-tools \
    lm-sensors \
    nut-server \
    nut-client \
    watchdog \
    logrotate \
    gzip

echo "[5/10] Configuring log rotation..."
cat > /etc/logrotate.d/data-diode <<EOF
$LOG_DIR/*.log {
    daily
    rotate 90
    compress
    delaycompress
    notifempty
    missingok
    create 0640 $USER $GROUP
    sharedscripts
    postrotate
        # Reload application if it's running
        systemctl reload data-diode >/dev/null 2>&1 || true
    endscript
}
EOF

echo "[6/10] Tuning kernel parameters for harsh environments..."
cat > /etc/sysctl.d/99-data-diode.conf <<EOF
# Network resilience for harsh environments
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=6
net.ipv4.tcp_retries2=10
net.ipv4.tcp_fin_timeout=30

# Memory management for long-running systems
vm.vfs_cache_pressure=50
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.overcommit_memory=1

# Filesystem limits
fs.file-max=65536

# Hardware watchdog (if supported)
# These might not exist on all systems
EOF

sysctl -p /etc/sysctl.d/99-data-diode.conf

echo "[7/10] Configuring hardware watchdog..."
if modprobe bcm2835_wdt 2>/dev/null || modprobe softdog 2>/dev/null; then
    echo "Hardware watchdog module loaded"

    # Enable watchdog service
    systemctl enable watchdog
    systemctl start watchdog

    # Configure watchdog daemon
    cat > /etc/watchdog.conf <<EOF
# Watchdog configuration for Data Diode
# Interval = 10 seconds (default)
# max-load-1 = 24 (prevent false positives during legitimate load)
watchdog-device = /dev/watchdog
temperature-device = /sys/class/thermal/thermal_zone0/temp
max-temperature = 75000
temperature-safety-margin = 10
EOF

    echo "Hardware watchdog configured"
else
    echo "Hardware watchdog not available on this platform"
fi

echo "[8/10] Configuring UPS monitoring (NUT)..."
# Configure NUT for UPS monitoring
if [ -f /etc/nut/ups.conf ]; then
    # Basic NUT configuration
    cat > /etc/nut/ups.conf <<EOF
# NUT UPS Configuration
MODE=netserver

# Add your UPS device here
# Example for USB UPS:
# [myups]
#       driver = usbhid-ups
#       port = auto
#       desc = "Data Diode UPS"
EOF

    # Enable NUT services
    systemctl enable nut-server
    systemctl start nut-server

    echo "UPS monitoring configured via NUT"
else
    echo "NUT not installed, UPS monitoring unavailable"
fi

echo "[9/10] Installing systemd service..."
cp deployment/data-diode.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable data-diode

echo "[10/10] Generating secure API token..."
# Generate secure token for Health API
API_TOKEN=$(openssl rand -hex 32)
echo "HEALTH_API_TOKEN=$API_TOKEN" >> /etc/data-diode/environment
chmod 600 /etc/data-diode/environment
echo "Health API token generated and saved to /etc/data-diode/environment"
echo ""
echo "IMPORTANT: Store this token securely for remote API access:"
echo "Token: $API_TOKEN"
echo ""

echo ""
echo "========================================"
echo "Deployment Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Copy your application to: $DEPLOY_DIR"
echo "2. Configure environment variables in: /etc/data-diode/environment"
echo "3. Start the service: systemctl start data-diode"
echo "4. Monitor logs: journalctl -u data-diode -f"
echo "5. Check health: curl -H 'X-Auth-Token: $API_TOKEN' http://localhost:4000/api/health"
echo ""
echo "For harsh environments, ensure:"
echo "- Industrial enclosure (IP67 rated)"
echo "- Wide-temperature components (-40°C to +85°C)"
echo "- Proper ventilation and heating"
echo "- UPS with sufficient battery capacity"
echo "- Secondary storage (SD cards wear out)"
echo ""
