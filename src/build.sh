#!/bin/bash
# Generate the tables, assemble the head, and put it on a disc.
#
#     ./build.sh
#
# Writes ../disk/HEAD.BIN and ../disk/head.dsk.  The tools are found on PATH,
# or at the places below, or wherever RASM= and IDSK= say:
#
#     RASM=/path/to/rasm IDSK=/path/to/iDSK ./build.sh
#
# rasm: https://github.com/EdouardBERGE/rasm   iDSK: https://github.com/cpcsdk/idsk
set -e
cd "$(dirname "$0")"
. ./tools.sh                    # RASM, IDSK, HXCFE, MAME - and the complaint
need RASM rasm
need IDSK iDSK
DISK=../disk

python3 mkhead.py               # P-C-S.BAS DATA -> headdata.inc, with its assertions

# rasm reports a failed assembly on stdout and still exits 0, so the exit code
# is worth nothing: look for the line that says it wrote something.
if ! "$RASM" head.asm -s | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Write binary file"; then
  echo "ASSEMBLY FAILED:"; "$RASM" head.asm -s 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -8
  exit 1
fi
mv -f HEAD.BIN "$DISK/HEAD.BIN"

rm -f "$DISK/head.dsk"
"$IDSK" "$DISK/head.dsk" -n >/dev/null 2>&1
"$IDSK" "$DISK/head.dsk" -i "$DISK/HEAD.BIN" -t 2 -f >/dev/null 2>&1
# The 1985 rules, if they are here. They are not in this repository -- see
# LICENSE-NOTE.md -- so tools/extract_nrl.sh makes NRL.BIN from a driver you
# supply. Without it the disc still builds and the program still runs; it
# just says so instead of speaking typed text.
if [ -f "$DISK/NRL.BIN" ]; then
  "$IDSK" "$DISK/head.dsk" -i "$DISK/NRL.BIN" -t 2 -f >/dev/null 2>&1
else
  # An empty stand-in, so VH.BAS still finds something to LOAD. AMSDOS
  # reports a missing file straight to BASIC and ON ERROR does not catch
  # it, so without this the program never starts at all. The head checks
  # for PUSH AF at NRLLOAD+&0BB8 before hooking the rules; zeros fail that
  # and it runs on its keys, which is the intended degraded mode.
  echo "note: no $DISK/NRL.BIN -- building without the letter-to-sound rules."
  echo "      tools/extract_nrl.sh <SSA-1.zip> makes one; see LICENSE-NOTE.md."
  STUB=$(mktemp -d)/NRL.BIN        # iDSK names the file after its basename
  python3 - "$STUB" <<'EOF'
import sys
body = bytes(6016)
h = bytearray(128); h[1:9], h[9:12] = b'NRL     ', b'BIN'; h[18] = 2
h[21], h[22] = 0x00, 0x20
h[24], h[25] = len(body) & 0xFF, len(body) >> 8
h[64], h[65] = h[24], h[25]
c = sum(h[:67]) & 0xFFFF; h[67], h[68] = c & 0xFF, c >> 8
open(sys.argv[1], 'wb').write(bytes(h) + body)
EOF
  "$IDSK" "$DISK/head.dsk" -i "$STUB" -t 2 -f >/dev/null 2>&1
  rm -rf "$(dirname "$STUB")"
fi
"$IDSK" "$DISK/head.dsk" -i VH.BAS           -t 0 -f >/dev/null 2>&1   # loads them, then the head
"$IDSK" "$DISK/head.dsk" -l
