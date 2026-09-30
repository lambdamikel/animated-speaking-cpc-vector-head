#!/bin/bash
# Reproduce disk/NRL.BIN from the 1985 Amstrad SSA-1 driver, which this
# repository does not ship.
#
#     ./extract_nrl.sh ~/Downloads/SSA-1.zip
#     ./extract_nrl.sh SSA-1.DSK
#     ./extract_nrl.sh SSA1.BIN
#
# Get the disc from CPCWiki:  https://www.cpcwiki.eu/imgs/6/65/SSA-1.zip
#
# The driver is self-relocating and will not sit still at a fixed address, so
# the only honest way to get a fixed copy is to let it relocate itself once,
# inside an emulator, and take the result away: tools/reloc.asm does the
# relocation, emu/grab_blob.lua watches for it to finish and dumps the image.
# Writes ../disk/NRL.BIN.
set -e
cd "$(dirname "$0")"
. ../src/tools.sh                       # RASM, IDSK, MAME, CPCROMS - and need
need RASM rasm
need IDSK iDSK

SRC=${1:?usage: extract_nrl.sh <SSA-1.zip | SSA-1.DSK | SSA1.BIN>}
[ -f "$SRC" ] || { echo "no such file: $SRC" >&2; exit 1; }
OUTBIN=../disk/NRL.BIN
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# --- 1. get the driver out of whatever was handed to us --------------------
case "$SRC" in
  *.zip|*.ZIP)  unzip -o -q "$SRC" -d "$T/z"
                SRC=$(find "$T/z" -iname '*.dsk' | head -1)
                [ -n "$SRC" ] || { echo "no .dsk inside that zip" >&2; exit 1; } ;;
esac
case "$SRC" in
  *.dsk|*.DSK)  ( cd "$T" && "$OLDPWD/$IDSK" "$(realpath "$SRC")" -g SSA1.BIN ) >/dev/null 2>&1 \
                  || "$IDSK" "$SRC" -g SSA1.BIN >/dev/null 2>&1
                [ -f SSA1.BIN ] && mv SSA1.BIN "$T/SSA1.BIN"
                SRC="$T/SSA1.BIN" ;;
esac
[ -f "$SRC" ] || { echo "could not find SSA1.BIN on that disc" >&2; exit 1; }

# 6144 bytes is a 128-byte AMSDOS header plus the 6016 the driver actually is.
python3 - "$SRC" "$T/payload" <<'PY'
import sys
b = open(sys.argv[1], 'rb').read()
if len(b) == 6144:   b = b[128:]          # strip the AMSDOS header
if len(b) != 6016:
    sys.exit(f"expected 6016 bytes of driver, got {len(b)} -- is that the SSA-1 driver?")
open(sys.argv[2], 'wb').write(b)
PY

# --- 2. assemble the relocator --------------------------------------------
"$RASM" reloc.asm -s 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -q "Write binary file" \
  || { echo "ASSEMBLY FAILED:"; "$RASM" reloc.asm -s 2>&1 | tail -8; exit 1; }
python3 -c "import sys; d=open('RELOC.BIN','rb').read(); open(sys.argv[1],'wb').write(d[128:])" "$T/reloc.raw"
rm -f RELOC.BIN rasmoutput.sym

# --- 3. let it relocate itself once, and take the result --------------------
DRV="$T/payload" RELOC="$T/reloc.raw" OUT="$T/blob" \
  ./mame.sh cpc6128 -autoboot_delay 2 -autoboot_script ../emu/grab_blob.lua 2>&1 \
  | grep -q "blob dumped" \
  || { echo "the driver did not relocate -- see emu/grab_blob.lua" >&2; exit 1; }

# --- 4. header it, and stop the interrupt ticker ---------------------------
python3 - "$T/blob" "$OUTBIN" <<'PY'
import sys
body = bytearray(open(sys.argv[1], 'rb').read())
assert len(body) == 6016, len(body)
# The driver is 5170 bytes -- its own AMSDOS header says so. The file is 6016
# because that is what came off the disc, and the last 846 bytes are whatever
# followed it there. After relocation in RAM they are whatever was in RAM, so
# zero them or the output is not reproducible.
body[0x1432:] = bytes(6016 - 0x1432)
body[0x844] = 0          # the driver's interrupt ticker, which we do not want
h = bytearray(128)
h[1:9], h[9:12] = b'NRL     ', b'BIN'
h[18] = 2
h[21], h[22] = 0x00, 0x20                          # load &2000
h[24], h[25] = len(body) & 0xFF, len(body) >> 8
h[64], h[65] = h[24], h[25]
c = sum(h[:67]) & 0xFFFF
h[67], h[68] = c & 0xFF, c >> 8
open(sys.argv[2], 'wb').write(bytes(h) + bytes(body))
print(f"wrote {sys.argv[2]}: {128 + len(body)} bytes")
PY

echo "Now run src/build.sh -- the disc will be built with the rules on it."
