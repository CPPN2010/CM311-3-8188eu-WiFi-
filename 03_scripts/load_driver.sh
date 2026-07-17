#!/system/bin/sh
# load_driver.sh - Load 8188eu WiFi driver on CM311-3 set-top box
# Usage: adb shell sh /data/local/tmp/load_driver.sh
#
# Prerequisites:
#   - 8188eu_v5_patched.ko and cfg80211.ko in /data/local/tmp/
#   - adb root granted

echo "=== Loading cfg80211 ==="
insmod /data/local/tmp/cfg80211.ko 2>&1

echo "=== Loading 8188eu (embedded firmware) ==="
insmod /data/local/tmp/8188eu_v5_patched.ko 2>&1

echo "=== Waiting for driver init ==="
sleep 3

echo "=== Loaded modules ==="
lsmod | grep -E 'cfg80211|8188eu'

echo "=== Bringing up wlan0 ==="
ip link set wlan0 up 2>&1
sleep 1
ip link show wlan0 2>&1

echo "=== Firmware/driver log ==="
dmesg | tail -10 | grep -iE "wlan|rtw|8188|firmware|cfg80211|panic|oops"
