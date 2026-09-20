#!/bin/bash
# What do the 1985 rules make of a word?
#
#     ./run_words.sh GOODBYE BROUGHT DIGITIZED
#     GOODBYE        PA2 GG1 UW2 PA2 DD1 PA2 BB1 YY1 PA1
#     BROUGHT        PA2 BB1 RR2 AW PA3 TT2 PA1
#     DIGITIZED      PA2 DD2 AY PA2 GG3 AY PA3 TT2 AY ZZ PA3 TT1 PA1
#
# Assembles a harness that calls the engine on each word in turn, runs it on
# an emulated CPC, reads the allophones back out of memory and prints them by
# name.  This is how every entry of the exception table in head.asm was
# arrived at: a respelling is tried, not guessed.
set -e
cd "$(dirname "$0")"
RASM=${RASM:-~/claude/midi80/toolchain/rasm/rasm}
IDSK=${IDSK:-~/claude/midi80/toolchain/idsk/iDSK}
MAME=${MAME:-../../tools/mame.sh}          # headless MAME with the CPC roms
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

python3 mkwords.py "$@" >/dev/null         # words.inc, which nrlwords.asm includes
$RASM nrlwords.asm -s 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Write binary file" \
  || { echo "ASSEMBLY FAILED"; $RASM nrlwords.asm 2>&1 | tail -5; exit 1; }
$IDSK "$T/words.dsk" -n >/dev/null 2>&1
$IDSK "$T/words.dsk" -i NRLWORDS.BIN -t 2 -f >/dev/null 2>&1
$IDSK "$T/words.dsk" -i ../disk/NRL.BIN -t 2 -f >/dev/null 2>&1
$IDSK "$T/words.dsk" -i NW.BAS -t 0 -f >/dev/null 2>&1
OUT=$("$MAME" cpc6128 -flop1 "$T/words.dsk" -autoboot_delay 2 \
        -autoboot_script ../emu/words.lua 2>&1 | grep "^=== " | head -1 | cut -c5-)

python3 - "$OUT" "$@" <<'PY'
import sys, re
blk = open('../src/headdata.inc').read().split('phnames:')[1]
names = [m.group(1).strip() for m in re.finditer(r'"([^"]{3})"', blk)][:64]
data, words = sys.argv[1], sys.argv[2:]
runs, cur = [], []
for b in ([int(x) for x in data.split(',')] if data and data != 'gave up' else []):
    if b == 0xFF: runs.append(cur); cur = []
    else: cur.append(b)
if not runs: sys.exit('the emulated machine produced nothing')
for w, r in zip(words, runs):
    print(f'{w:<14} {" ".join(names[i] for i in r)}')
PY
