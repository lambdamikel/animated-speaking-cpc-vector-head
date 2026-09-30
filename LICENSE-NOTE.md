# What is and is not covered by the licence

The short version: **everything written for this project is GPL-3. Two files
are not ours and are not GPL**, and one piece of prior art is cited rather
than reproduced. This note says which is which, because a repository that
ships a 1985 binary should be explicit about it rather than quiet.

## GPL-3: everything written for this project

© 2026 Michael Wessel (LambdaMikel) and Claude, under the GPL-3 in
[`LICENSE`](LICENSE) — the same licence as LambdaSpeak.

| | |
|---|---|
| `src/head.asm`, `src/line.asm`, `src/headdata.inc` | the Z80 program |
| `src/mkhead.py`, `src/preview.py`, `src/build.sh`, `src/dist.sh` | the build |
| `tools/dz80.py`, `tools/walk.py`, `tools/reloc.asm`, `tools/mkwords.py`, `tools/nrlwords.asm` | the disassembler and the extraction recipe |
| `emu/*.lua`, `tools/*.sh` | the emulator harness |
| `disk/HEAD.BIN` | built from the above |
| `README.md`, `docs/*.png` | the write-up and its screenshots |
| `original/` | Michael's 1985 BASIC and the digitised head data |

The head geometry itself was digitised by hand by Michael in 1985, off a
*P.M. Computerheft* article. That work is his.

## Not ours: the 1985 Amstrad SSA-1 driver

**`tools/SSA1.BIN`** is the 1985 Amstrad SSA-1 speech driver.
**`disk/NRL.BIN`** is that same driver, relocated to `&0200` and with one
flag cleared, as [`tools/reloc.asm`](tools/reloc.asm) describes.
**`disk/head.dsk`** and **`disk/head.hfe`** are built discs and therefore
contain `NRL.BIN` too.

> **© 1985 Amstrad plc. Not covered by the GPL-3 above.** Amstrad retains
> copyright. These files are included unmodified in substance, for
> provenance and because the program calls the driver's letter-to-sound
> rules directly as a subroutine.

They are here on the same preservation basis the Amstrad CPC archives have
used for decades: the SSA-1 driver has been openly distributed by
[CPCWiki](https://cpcwiki.eu/index.php?title=Amstrad_SSA-1_Speech_Synthesizer)
and [CPCrulez](https://cpcrulez.fr/applications_music-amstrad_ssa-1_speech_synthesizer_software.htm)
— cassette dumps, DSK drivers for emulators, and manual scans — for many
years. Nothing here is sold, and no copyright notice has been altered.

**Being precise about the permission, because it is often overstated.**
Amstrad and Locomotive Software have granted permission for the CPC **ROMs**
to be distributed with emulators — Cliff Lawson for Amstrad's BASIC ROM,
Richard Clayton for Locomotive's firmware ROM — both retaining copyright.
That is a real permission, and it is *not* this file: the SSA-1 driver is
peripheral software that shipped on cassette with the hardware, and we know
of no specific grant covering it. It is published here as preservation of a
1985 peripheral driver, not under a licence we can point at.

**If Amstrad or a successor in title would rather it were not here, say so
and it goes**, and the program will still build: `tools/reloc.asm` and
`emu/grab_blob.lua` reproduce `NRL.BIN` from a driver you supply yourself.

## Cited, not reproduced: Parke's head

The wireframe descends from F. I. Parke, *"Computer generated animation of
faces"*, ACM Annual Conference 1972
([doi:10.1145/800193.569955](https://dl.acm.org/doi/10.1145/800193.569955)).
**No figure from that paper and no frame of the film is reproduced here.**
The links go to the work itself. What is in `original/` is Michael's own
1985 digitisation.

## Public domain: the letter-to-sound rules themselves

The algorithm the driver implements is the **NRL letter-to-sound rules** —
Elovitz, Johnson, McHugh and Shore, *Automatic Translation of English Text
to Phonetics by Means of Letter-to-Sound Rules*, NRL Report 7948, 1976
([DTIC](https://apps.dtic.mil/sti/pdfs/ADA021929.pdf)). A work of the US
Government, so **the rules are free to implement**; only Amstrad's 1985
*expression* of them is not.

That distinction is the way out of this whole section. A clean
implementation of the NRL rules — there are public-domain ones, including
Wasser's 1985 C version — would let this program drop `NRL.BIN` entirely.
That is planned for LambdaSpeak 4's `|SAYSPO`, and this program could then
use it.
