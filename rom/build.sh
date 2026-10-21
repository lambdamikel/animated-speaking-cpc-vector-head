#!/bin/bash
# Build VH.ROM.  Needs HEAD.BIN (../disk, from ../src/build.sh) and an
# NRL.BIN you supply -- see README.md and ../LICENSE-NOTE.md.
#
#     NRL=/path/to/NRL.BIN ./build.sh
set -e
cd "$(dirname "$0")"
. ../src/tools.sh
need RASM rasm

# LSAI=1 builds the redistributable ROM: no Amstrad engine, the card is asked
# through &E9 instead. Anything else builds the classic one, which runs on any
# CPC with any SP0256 card and carries the 1985 engine.
if [ -n "$LSAI" ]; then
  OUT=VHLSAI.ROM; DEF="-DLSAI=1"; HEADSRC=HEAD-LSAI.BIN
else
  OUT=VH.ROM;     DEF="";         HEADSRC=HEAD.BIN
fi

# The head itself is built differently for the two: -DLSAI swaps its
# letter-to-sound for the port exchange.
( cd ../src && "$RASM" head.asm $DEF -s >/dev/null && mv -f HEAD.BIN "../rom/$HEADSRC" )
[ -f "$HEADSRC" ] || { echo "the head did not build"; exit 1; }
dd if="$HEADSRC" of=HEAD.RAW bs=1 skip=128 status=none

if [ -z "$LSAI" ]; then
  NRL=${NRL:-./NRL.BIN}
  [ -f "$NRL" ] || { echo "no $NRL -- see README.md; the 1985 rules are not ours to ship"; exit 1; }
  dd if="$NRL" of=NRL.RAW bs=1 skip=128 status=none
fi

# rasm exits 0 on a failed assembly, so the exit code is worth nothing.
if ! "$RASM" vhrom.asm $DEF -s | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Write binary file"; then
  echo "ASSEMBLY FAILED:"; "$RASM" vhrom.asm $DEF -s 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -8
  exit 1
fi
mv -f VH.ROM "$OUT" 2>/dev/null || true
rm -f HEAD.RAW NRL.RAW rasmoutput.sym "$HEADSRC"
ls -l "$OUT"
