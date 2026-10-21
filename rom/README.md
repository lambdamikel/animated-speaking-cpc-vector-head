# The vector head as an expansion ROM

16 KB, a background ROM offering one RSX. `|VH` and the head runs: no disc, no
`MEMORY` statement, no `LOAD`. Built for LambdaSpeak AI, whose ROM emulation
answers upper-ROM reads out of flash, so it needs no ROM board -- but it is an
ordinary CPC ROM and a real ROM box will run it.

```
    LSAI=1 ./build.sh     # VHLSAI.ROM -- publishable, needs LambdaSpeak AI
    NRL=/path/to/NRL.BIN ./build.sh   # VH.ROM -- runs anywhere
```

## Two builds

|  | `VH.ROM` | `VHLSAI.ROM` |
| --- | --- | --- |
| letter-to-sound | Amstrad's 1985 engine, in the ROM | asked of the card, `&E9` |
| size used | 13,740 of 16,384 | **7,760** |
| runs on | any CPC with any SP0256 card | LambdaSpeak AI |
| redistributable | **no** | **yes** |

### Which firmware `VHLSAI.ROM` needs

`&E9` -- the command that hands allophones back -- was added to LambdaSpeak AI
in October 2026, alongside `&E8`. A card running firmware older than that will
not answer, and the ROM will say so and fall back to its built-in sentence
rather than hanging. If `|VH` reports "No LambdaSpeak AI answered" on a card
that is plugged in and working, the firmware is what to check first.

The exchange itself has not yet been run against real hardware: it is verified
on the host, and in MAME only against MAME's own SSA-1, which exercises the
timeout rather than the reply. The classic `VH.ROM` has no such dependency.

`VHLSAI.ROM` carries none of Amstrad's driver -- checked by searching it for
323 distinctive 32-byte runs of the 1985 engine and finding none, where
`VH.ROM` contains all of them. The rules it uses instead are the same Naval
Research Laboratory rules, reimplemented on the card from the 1976 report.

On hardware that does not answer `&E9` -- a real SSA-1, say -- the LambdaSpeak
build degrades rather than hanging: the probe times out after about a quarter
of a second, and the head draws, speaks its built-in sentence and says there is
no prompt, exactly as the classic build does without `NRL.BIN`. Verified in
MAME against MAME's own SSA-1.

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
