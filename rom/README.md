# The vector head as an expansion ROM

16 KB, a background ROM offering one RSX. `|VH` and the head runs: no disc, no
`MEMORY` statement, no `LOAD`. Built for LambdaSpeak AI, whose ROM emulation
answers upper-ROM reads out of flash, so it needs no ROM board -- but it is an
ordinary CPC ROM and a real ROM box will run it.

```
    ./build.sh            # needs NRL.BIN; see below
```

**The rules are not here and neither is the built ROM.** `VH.ROM` contains the
1985 NRL letter-to-sound rules, which are © 1985 Amstrad plc and not ours to
redistribute -- see `../LICENSE-NOTE.md`. `build.sh` takes `NRL.BIN` from a
driver you supply, exactly as `tools/extract_nrl.sh` does for the disc build,
and `.gitignore` keeps both the rules and the ROM out of the repository.

## Two things shape it

**The head returns to BASIC.** `start` saves SP and puts it back when the line
editor quits, so the RSX `CALL`s it rather than using `MC START PROGRAM`, which
would reset the firmware and never come back.

**Both ROMs have to be switched off while it runs**, and that cannot be done
by code running inside a ROM -- the instruction after the switch would be
fetched from the RAM underneath. Hence a ten-byte stub copied to `#9E00` and
jumped to.

* The **upper** ROM shadows `#C000`, where the screen is. The head reads screen
  memory -- `ldir ; screen -> buffer` in its double-buffered blit -- and with
  the ROM in the way those reads return ROM.
* The **lower** ROM shadows `#2000`, where the rules go, and this one is easy
  to miss. The `LDIR` puts them there happily, because writes always reach the
  RAM underneath; but the head reads a signature byte back to decide whether
  the rules arrived, and with the lower ROM in the way it read the operating
  system instead. Symptom: the head ran, drew, and reported "NRL.BIN was not
  loaded" while the rules sat in the RAM beneath it.

Verified in MAME with `emu/romtest.lua`, which posts `|VH` and reads back the
two payloads: `#8000` holds `C3`, the head's own `jp start`; `#2BB8` holds
`F5`, the signature `installnrl` looks for; and the prompt comes up with the
rules translating typed text into allophones.

## Where the pieces go

| | |
| --- | --- |
| `#C000` | ROM header, name table, the RSX |
| `#2000` | the NRL rules, 6016 bytes |
| `#8000` | the head, 7635 bytes |
| `#9E00` | the stub, above the head's last byte and below AMSDOS |

13,651 bytes of payload in a 16,384-byte ROM.
