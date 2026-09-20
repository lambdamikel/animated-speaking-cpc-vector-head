#!/bin/bash
# Assemble the vector head and put it on a disc.
set -e
cd "$(dirname "$0")"
RASM=~/claude/midi80/toolchain/rasm/rasm
IDSK=~/claude/midi80/toolchain/idsk/iDSK
python3 mkhead.py
if ! $RASM head.asm -s | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Write binary file"; then
  echo "ASSEMBLY FAILED:"; $RASM head.asm -s 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | tail -8; exit 1
fi
rm -f head.dsk
$IDSK head.dsk -n >/dev/null 2>&1
$IDSK head.dsk -i HEAD.BIN -t 2 -f >/dev/null 2>&1
$IDSK head.dsk -i NRL.BIN -t 2 -f >/dev/null 2>&1     # the 1985 letter-to-sound rules
$IDSK head.dsk -i VH.BAS -t 0 -f >/dev/null 2>&1      # loads it, then the head
$IDSK head.dsk -l
