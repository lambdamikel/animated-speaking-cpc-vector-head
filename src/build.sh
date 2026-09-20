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
"$IDSK" "$DISK/head.dsk" -i "$DISK/NRL.BIN"  -t 2 -f >/dev/null 2>&1   # the 1985 rules
"$IDSK" "$DISK/head.dsk" -i VH.BAS           -t 0 -f >/dev/null 2>&1   # loads them, then the head
"$IDSK" "$DISK/head.dsk" -l
