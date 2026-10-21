#!/bin/bash
# Build VH.ROM.  Needs HEAD.BIN (../disk, from ../src/build.sh) and an
# NRL.BIN you supply -- see README.md and ../LICENSE-NOTE.md.
#
#     NRL=/path/to/NRL.BIN ./build.sh
set -e
cd "$(dirname "$0")"
. ../src/tools.sh
need RASM rasm

HEAD=${HEAD:-../disk/HEAD.BIN}
NRL=${NRL:-./NRL.BIN}
[ -f "$HEAD" ] || { echo "no $HEAD -- run ../src/build.sh first"; exit 1; }
[ -f "$NRL" ]  || { echo "no $NRL -- see README.md; the 1985 rules are not ours to ship"; exit 1; }

# The .BIN files carry a 128-byte AMSDOS header the ROM has no use for.
dd if="$HEAD" of=HEAD.RAW bs=1 skip=128 status=none
dd if="$NRL"  of=NRL.RAW  bs=1 skip=128 status=none

# rasm exits 0 on a failed assembly, so the exit code is worth nothing.
if ! "$RASM" vhrom.asm -s | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Write binary file"; then
  echo "ASSEMBLY FAILED:"; "$RASM" vhrom.asm -s 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -8
  exit 1
fi
rm -f HEAD.RAW NRL.RAW rasmoutput.sym
ls -l VH.ROM
