#!/system/bin/sh
# wifi_auto_load.sh - Auto load 8188eu driver and connect WiFi on boot
# Called by /vendor/etc/init/init.wifi_auto.rc on sys.boot_completed=1
# WiFi config (SSID/PSK) is read from /data/local/tmp/wifi_config.conf

LOG=/data/local/tmp/wifi_auto.log
WPA=/data/local/tmp/wpa_supplicant_wext
CLI=/data/local/tmp/wpa_cli_wext
CTRL=/data/local/tmp/wpa_ctrl
CONF=/data/local/tmp/wifi_config.conf

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> $LOG
}

log "=== WiFi auto load started ==="

# Wait for system to stabilize
sleep 5

# Load cfg80211 if not loaded
if ! lsmod | grep -q cfg80211; then
    log "Loading cfg80211..."
    insmod /data/local/tmp/cfg80211.ko 2>&1 >> $LOG
    sleep 1
fi

# Load 8188eu if not loaded
if ! lsmod | grep -q 8188eu; then
    log "Loading 8188eu driver..."
    insmod /data/local/tmp/8188eu_v5_patched.ko 2>&1 >> $LOG
    sleep 3
fi

# Bring up wlan0
if ! ip link show wlan0 2>/dev/null | grep -q "state UP"; then
    log "Bringing up wlan0..."
    ip link set wlan0 up 2>&1 >> $LOG
    sleep 2
fi

# Check WiFi config exists
if [ ! -f "$CONF" ]; then
    log "ERROR: $CONF not found, cannot connect WiFi"
    log "Create $CONF with content:"
    log '  SSID=YourWiFiName'
    log '  PSK=YourPassword'
    exit 1
fi

# Read SSID and PSK from config
source $CONF
log "Connecting to SSID: $SSID"

# Prepare control interface
mkdir -p $CTRL
chmod 755 $CTRL

# Create wpa config
cat > /data/local/tmp/wpa_wext.conf << EOF
ctrl_interface=$CTRL
update_config=1
EOF

# Kill old wpa_supplicant
killall wpa_supplicant_wext 2>/dev/null
sleep 1

# Start wpa_supplicant
log "Starting wpa_supplicant_wext..."
$WPA -i wlan0 -c /data/local/tmp/wpa_wext.conf -D wext -B >> $LOG 2>&1
sleep 3

# Check wpa running
if ! pidof wpa_supplicant_wext > /dev/null; then
    log "ERROR: wpa_supplicant_wext failed to start"
    exit 1
fi

# Add network and configure
NETID=$($CLI -i wlan0 -p $CTRL add_network 2>&1)
log "Network ID: $NETID"
$CLI -i wlan0 -p $CTRL set_network $NETID ssid "\"$SSID\"" >> $LOG 2>&1
$CLI -i wlan0 -p $CTRL set_network $NETID psk "\"$PSK\"" >> $LOG 2>&1
$CLI -i wlan0 -p $CTRL enable_network $NETID >> $LOG 2>&1
$CLI -i wlan0 -p $CTRL save_config >> $LOG 2>&1

# Wait for connection
log "Waiting for WiFi connection..."
for i in $(seq 1 20); do
    sleep 1
    STATE=$($CLI -i wlan0 -p $CTRL status 2>&1 | grep wpa_state= | cut -d= -f2)
    log "  [$i] state=$STATE"
    if [ "$STATE" = "COMPLETED" ]; then
        log "WiFi CONNECTED!"
        break
    fi
done

# Trigger DHCP
if [ "$STATE" = "COMPLETED" ]; then
    log "Triggering DHCP..."
    dhcpcd wlan0 >> $LOG 2>&1 &
    sleep 5
    IP=$(ip addr show wlan0 | grep 'inet ' | awk '{print $2}')
    log "IP address: $IP"
fi

log "=== WiFi auto load completed ==="
