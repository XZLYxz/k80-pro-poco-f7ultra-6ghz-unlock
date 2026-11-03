#!/system/bin/sh
MODDIR=${0%/*}
BB=/data/adb/magisk/busybox
BOOTID=$(cat /proc/sys/kernel/random/boot_id)
ORIGINAL=/vendor/lib/modules/qca_cld3_peach_v2.ko
EXPECTED_KERNEL=6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k
EXPECTED_ROM=OS3.0.302.0.WOMMIXM
ORIGINAL_HASH=7c819c0f62642272466673e337e8bba64b95a624bcd8dbd62895666cf1a14f5d
TEST_HASH=ce569057afb29cd691c84391f2d278d3e2dc235e851104d193ef69d0ff8f5335
CFG_HASH=d9786ba2cd67cc1a569d1f101abbf0b96b51c5093f6ef563936616f9b0ac5732
hash_file() { "$BB" sha256sum "$1" | "$BB" awk '{print $1}'; }
wifi_enabled() { /system/bin/cmd wifi status 2>/dev/null | "$BB" grep -q '^Wifi is enabled'; }
has_6g() { /system/bin/iw phy 2>/dev/null | "$BB" grep -q '5955.*MHz'; }
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$MODDIR/boot.log"; }
state() { echo "$*" > "$MODDIR/status"; log "$*"; }
wifi_command() {
 # Binder must receive pipe/null descriptors, not the protected module log file.
 output=$("$BB" timeout 20 /system/bin/cmd wifi "$@" 2>&1)
 rc=$?
 [ -n "$output" ] && log "$output"
 return "$rc"
}
check_versions() {
 [ "$(getprop ro.product.device)" = miro ] || return 1
 [ "$(getprop ro.build.version.incremental)" = "$EXPECTED_ROM" ] || return 1
 [ "$(uname -r)" = "$EXPECTED_KERNEL" ] || return 1
 [ "$(hash_file "$ORIGINAL")" = "$ORIGINAL_HASH" ] || return 1
 [ "$(hash_file "$MODDIR/driver.ko")" = "$TEST_HASH" ] || return 1
 [ "$(hash_file /vendor/etc/wifi/peach_v2/WCNSS_qcom_cfg.ini)" = "$CFG_HASH" ] || return 1
}
if [ "${1:-}" = --check ]; then
 if check_versions; then echo 'Version and hashes: MATCH'; exit 0; fi
 echo 'Version or hash mismatch'; exit 1
fi
# This guard runs before any driver change, including on a subsequent boot.
if [ -s "$MODDIR/pending_boot" ]; then
 previous=$(cat "$MODDIR/pending_boot")
 if [ "$previous" != "$BOOTID" ]; then
  touch "$MODDIR/disable"
  state 'AUTO_DISABLED: reboot occurred before the 120-second observation finished; original driver retained'
  exit 0
 fi
fi
[ -e "$MODDIR/disable" ] && exit 0
[ -e "$MODDIR/remove" ] && exit 0
# A per-boot lock prevents accidental concurrent reloads.
if [ -e "$MODDIR/running_boot" ] && [ "$(cat "$MODDIR/running_boot")" = "$BOOTID" ]; then exit 0; fi
echo "$BOOTID" > "$MODDIR/running_boot"
trap 'rm -f "$MODDIR/running_boot"' EXIT
mv -f "$MODDIR/boot.log" "$MODDIR/previous-boot.log" 2>/dev/null
exec >> "$MODDIR/boot.log" 2>&1
state 'WAITING_FOR_BOOT'
i=0
while [ "$(getprop sys.boot_completed)" != 1 ]; do
 [ "$i" -ge 120 ] && { state 'SKIPPED: boot not completed'; exit 0; }
 sleep 2; i=$((i+1))
done
sleep 15
state 'CHECKING_VERSION_AND_WIFI'
[ -e "$MODDIR/disable" ] && exit 0
[ -e "$MODDIR/remove" ] && exit 0
check_versions || { touch "$MODDIR/disable"; state 'AUTO_DISABLED: ROM/kernel/config/driver hash mismatch'; exit 0; }
# Respect Wi-Fi off: wait briefly for the user, never enable it on their behalf.
i=0
while ! wifi_enabled; do
 [ "$i" -ge 60 ] && { state 'SKIPPED: Wi-Fi remains off; use module Action after enabling Wi-Fi'; exit 0; }
 sleep 2; i=$((i+1))
done
if has_6g; then state 'ACTIVE: 6 GHz already registered; reload skipped'; exit 0; fi
state 'APPLYING: normal unload and temporary driver load'
echo "$BOOTID" > "$MODDIR/pending_boot"
sync
wifi_command set-wifi-enabled disabled
sleep 3
if ! /system/bin/rmmod qca_cld3_peach_v2; then
 rm -f "$MODDIR/pending_boot"
 touch "$MODDIR/disable"
 wifi_command set-wifi-enabled enabled
 state 'AUTO_DISABLED: normal unload refused; no force used'
 exit 0
fi
if ! /system/bin/insmod "$MODDIR/driver.ko"; then
 /system/bin/insmod "$ORIGINAL"
 touch "$MODDIR/disable"
 wifi_command set-wifi-enabled enabled
 state 'AUTO_DISABLED: test load failed; original driver reload attempted'
 exit 0
fi
# The framework can finish an old disable transition after the new driver loads.
# Confirm the enabled state and usable 6 GHz channel, with bounded retries.
i=0
ready=0
while [ "$i" -lt 4 ]; do
 wifi_command set-wifi-enabled enabled
 sleep 8
 wifi_command force-country-code enabled US
 sleep 2
 if wifi_enabled && /system/bin/iw phy | "$BB" grep '5955.*MHz' | "$BB" grep -qv disabled; then
  ready=1
  break
 fi
 log "Wi-Fi service not ready; retry $i"
 i=$((i+1))
done
if [ "$ready" != 1 ] || ! has_6g; then
 touch "$MODDIR/disable"
 state 'AUTO_DISABLED: no 6 GHz channels; reboot to restore original driver'
 exit 0
fi
state 'OBSERVING: 6 GHz registered, waiting 120 seconds before marking success'
sleep 120
if has_6g; then
 rm -f "$MODDIR/pending_boot"
 state 'ACTIVE: version matched; 6 GHz registered; observation completed'
else
 touch "$MODDIR/disable"
 state 'AUTO_DISABLED: 6 GHz disappeared; reboot to restore original driver'
fi
