#!/bin/bash
# Headless MAME: no window, no sound, so a Lua script can drive the emulated
# machine and read its memory.  CPCROMS must hold the cpc6128 ROM set.
#
#     ./mame.sh cpc6128 -flop1 ../disk/head.dsk -autoboot_script ../emu/lay6.lua
#
# Drop the "-video none -sound none" to watch it, or run MAME yourself:
#     mame cpc6128 -flop1 ../disk/head.dsk -autoboot_delay 3 -autoboot_command 'RUN"VH\n'
. "$(dirname "$0")/../src/tools.sh"
exec env -u WAYLAND_DISPLAY GDK_BACKEND=x11 xvfb-run -a \
  "$MAME" -rompath "$CPCROMS" -video none -sound none "$@"
