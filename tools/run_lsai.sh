#!/bin/bash
# Does the ROM's &E9 exchange work?
#
#     ./run_lsai.sh
#     === PASS: the &E9 exchange works end to end
#
# VHLSAI.ROM has no letter-to-sound engine of its own -- that is the whole
# point of it, since Amstrad's cannot be redistributed -- so it asks a
# LambdaSpeak AI for allophones over &FBEE instead. MAME has an SSA-1 but not
# that card, so emu/lsai_stub.lua stands in for one: it collects the text
# after an &E9 and answers the way the firmware does, with a sync byte, a
# count and that many allophones. The script then checks that exactly those
# allophones reached the head's own buffer.
#
# It does NOT test the rules. Those are checked on the host against
# say_rules, byte for byte. What had never been exercised anywhere is the
# protocol between the ROM and the card, and this is that test.
set -e
cd "$(dirname "$0")"
. ../src/tools.sh
[ -f ../rom/VHLSAI.ROM ] || { echo "../rom/VHLSAI.ROM is missing -- run rom/build.sh first" >&2; exit 1; }

# The stub reads the head's HOOKED, PHONBUF and SAYTAIL out of a symbol file,
# so regenerate it for THIS build before looking at it. Those three addresses
# used to be written into the stub and went stale twice -- they move whenever
# anything earlier in head.asm changes size -- and a stale one reports that the
# head did not hook the card, which is a true statement about nothing.
need RASM rasm
SYMS=$(cd ../src && pwd)/rasmoutput.sym
(cd ../src && "$RASM" head.asm -DLSAI=1 -s >/dev/null)
export SYMS

OUT=$(./mame.sh cpc6128 -exp rom -rom1 ../rom/VHLSAI.ROM \
        -autoboot_script ../emu/lsai_stub.lua 2>&1 | grep "^=== ")
echo "$OUT"
echo "$OUT" | grep -q "^=== PASS" || exit 1
