#!/system/bin/sh
echo "=== kill old wpa ==="
killall wpa_supplicant_wext 2>/dev/null
sleep 1

echo "=== ensure wlan0 up ==="
ip link set wlan0 up 2>&1
sleep 1

echo "=== ensure ctrl dir ==="
mkdir -p /data/local/tmp/wpa_ctrl
chmod 755 /data/local/tmp/wpa_ctrl

echo "=== push config ==="
cat > /data/local/tmp/wpa_wext.conf << 'EOF'
ctrl_interface=/data/local/tmp/wpa_ctrl
update_config=1
EOF

echo "=== start wpa_supplicant_wext (background) ==="
/data/local/tmp/wpa_supplicant_wext -i wlan0 -c /data/local/tmp/wpa_wext.conf -D wext -B -dd 2>&1
echo "wpa exit code: $?"

sleep 3
echo ""
echo "=== wpa pid ==="
pidof wpa_supplicant_wext

echo ""
echo "=== wpa_cli status ==="
/data/local/tmp/wpa_cli_wext -i wlan0 -p /data/local/tmp/wpa_ctrl status 2>&1

echo ""
echo "=== trigger scan ==="
/data/local/tmp/wpa_cli_wext -i wlan0 -p /data/local/tmp/wpa_ctrl scan 2>&1
echo "scan triggered, waiting 8s..."
sleep 8

echo ""
echo "=== scan_results ==="
/data/local/tmp/wpa_cli_wext -i wlan0 -p /data/local/tmp/wpa_ctrl scan_results 2>&1

echo ""
echo "=== dmesg tail (wlan/rtw/panic) ==="
dmesg | tail -15 | grep -iE "wlan|rtw|wpa|panic|oops|scan" || echo "no relevant logs"
