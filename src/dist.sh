#!/bin/bash
# Build the disc for a real machine: a DSK, and an HFE for a Gotek or HxC.
#
#     ./dist.sh                       # or  HXCFE=/path/to/hxcfe ./dist.sh
#
# hxcfe is the HxC command line tool (https://hxc2001.com/).  It is linked
# against libhxcfe.so, so LD_LIBRARY_PATH has to point at its directory.
set -e
cd "$(dirname "$0")"
. ./tools.sh
need HXCFE hxcfe
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-$(dirname "$HXCFE")}
DISK=../disk

./build.sh >/dev/null
"$HXCFE" -finput:"$DISK/head.dsk" -foutput:"$DISK/head.hfe" -conv:HXC_HFE >/dev/null 2>&1
echo "head.dsk : $("$IDSK" "$DISK/head.dsk" -l 2>/dev/null | grep -c '\.') files"
"$IDSK" "$DISK/head.dsk" -l 2>/dev/null | grep 'BIN\|BAS' | sed 's/^/           /'
echo "head.hfe : $(stat -c%s "$DISK/head.hfe") bytes"
