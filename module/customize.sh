[ "$BOOTMODE" = true ] || abort 'Install only in Magisk app.'
[ "$(getprop ro.product.device)" = miro ] || abort 'This module is only for miro.'
[ "$(getprop ro.build.version.incremental)" = OS3.0.302.0.WOMMIXM ] || abort 'ROM mismatch.'
[ "$(uname -r)" = 6.6.118-android15-8-ge56cf6b09cca-ab15511674-4k ] || abort 'Kernel mismatch.'
EXPECTED=7c819c0f62642272466673e337e8bba64b95a624bcd8dbd62895666cf1a14f5d
ACTUAL=$(sha256sum /vendor/lib/modules/qca_cld3_peach_v2.ko | awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || abort 'Original driver mismatch.'
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
