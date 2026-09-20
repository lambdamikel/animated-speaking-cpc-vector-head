#!/bin/bash
# Build the disc for a real machine: a DSK, and an HFE for a Gotek or HxC.
#
#     IDSK=... HXCFE=... ./dist.sh
#
# hxcfe is the HxC command line tool (https://hxc2001.com/). It is linked
# against libhxcfe.so, so LD_LIBRARY_PATH has to point at its directory.
set -e
cd "$(dirname "$0")"
./build.sh >/dev/null
IDSK=${IDSK:-$(command -v iDSK || echo ~/claude/midi80/toolchain/idsk/iDSK)}
HXCFE=${HXCFE:-$(command -v hxcfe || echo ~/claude/midi80/toolchain/hxc/build/hxcfe)}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-$(dirname "$HXCFE")}

"$HXCFE" -finput:head.dsk -foutput:head.hfe -conv:HXC_HFE >/dev/null 2>&1
echo "head.dsk : $("$IDSK" head.dsk -l 2>/dev/null | grep -c '\.') files"
"$IDSK" head.dsk -l 2>/dev/null |  grep BIN\|BAS | sed 's/^/           /'
echo "head.hfe : $(stat -c%s head.hfe) bytes"
