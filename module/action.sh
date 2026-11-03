#!/system/bin/sh
MODDIR=${0%/*}
echo 'Current status:'
cat "$MODDIR/status" 2>/dev/null
echo 'Version check:'
sh "$MODDIR/service.sh" --check || exit 1
if [ -e "$MODDIR/disable" ]; then
 echo 'Disabled: review boot.log and the previous reboot before re-enabling.'
 exit 0
fi
if [ ! -s "$MODDIR/pending_boot" ] && [ ! -e "$MODDIR/running_boot" ]; then
 sh "$MODDIR/service.sh" >/dev/null 2>&1 &
 echo 'Check started. Wi-Fi may disconnect briefly if a reload is needed.'
fi
