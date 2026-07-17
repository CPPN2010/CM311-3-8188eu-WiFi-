#!/system/bin/sh
# connect_wifi.sh - Connect to WiFi AP using wpa_supplicant_wext
# Usage: adb shell sh /data/local/tmp/connect_wifi.sh <SSID> <PASSWORD>
#
# Prerequisites:
#   - Driver loaded and wlan0 up (run load_driver.sh first)
#   - wpa_supplicant_wext and wpa_cli_wext in /data/local/tmp/

SSID="$1"
PSK="$2"

if [ -z "$SSID" ] || [ -z "$PSK" ]; then
    echo "Usage: $0 <SSID> <PASSWORD>"
    exit 1
fi

WPA=/data/local/tmp/wpa_supplicant_wext
CLI=/data/local/tmp/wpa_cli_wext
CTRL=/data/local/tmp/wpa_ctrl

echo "=== Kill old wpa_supplicant ==="
killall wpa_supplicant_wext 2>/dev/null
sleep 1

echo "=== Ensure wlan0 up ==="
ip link set wlan0 up 2>&1
sleep 1

echo "=== Prepare control interface dir ==="
mkdir -p $CTRL
chmod 755 $CTRL

echo "=== Create wpa config ==="
cat > /data/local/tmp/wpa_wext.conf << EOF
ctrl_interface=$CTRL
update_config=1
EOF

echo "=== Start wpa_supplicant_wext (background) ==="
$WPA -i wlan0 -c /data/local/tmp/wpa_wext.conf -D wext -B 2>&1
sleep 3

echo "=== wpa_cli status ==="
$CLI -i wlan0 -p $CTRL status 2>&1

echo ""
echo "=== Add network and configure ==="
NETID=$($CLI -i wlan0 -p $CTRL add_network 2>&1)
echo "network id: $NETID"

$CLI -i wlan0 -p $CTRL set_network $NETID ssid "\"$SSID\"" 2>&1
$CLI -i wlan0 -p $CTRL set_network $NETID psk "\"$PSK\"" 2>&1
$CLI -i wlan0 -p $CTRL enable_network $NETID 2>&1
$CLI -i wlan0 -p $CTRL save_config 2>&1

echo ""
echo "=== Waiting for connection (20s max) ==="
for i in $(seq 1 20); do
    sleep 1
    STATE=$($CLI -i wlan0 -p $CTRL status 2>&1 | grep wpa_state= | cut -d= -f2)
    echo "  [$i] state=$STATE"
    if [ "$STATE" = "COMPLETED" ]; then
        echo "  === CONNECTED ==="
        break
    fi
done

echo ""
echo "=== Final status ==="
$CLI -i wlan0 -p $CTRL status 2>&1

echo ""
echo "=== Trigger DHCP ==="
dhcpcd wlan0 2>&1 &
sleep 5

echo ""
echo "=== IP address ==="
ip addr show wlan0 2>&1

echo ""
echo "=== Route ==="
ip route 2>&1 | grep wlan0
