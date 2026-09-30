# What is and is not in this repository

**Everything here is GPL-3 and ours.** No third-party binary is shipped. That
takes one step to set up and is worth the step.

## The 1985 Amstrad driver is not here

The program speaks typed English by calling the **NRL letter-to-sound rules**
as a subroutine, and the copy of those rules it uses is the one inside
Amstrad's 1985 **SSA-1 speech driver**. That driver is © 1985 Amstrad plc.
It is not ours to redistribute, so it is not in this repository, in any file,
including the disc images.

Get it yourself — it is one download:

```sh
# https://www.cpcwiki.eu/imgs/6/65/SSA-1.zip
tools/extract_nrl.sh ~/Downloads/SSA-1.zip     # writes disk/NRL.BIN
src/dist.sh                                    # and now the disc has the rules
```

`tools/extract_nrl.sh` is ours. It takes the driver, lets it relocate itself
**once** inside an emulator for a fixed base of `&0200`, and takes the result
away — `tools/reloc.asm` does the relocation, `emu/grab_blob.lua` drives it.
The driver is self-relocating and will not sit still otherwise; that is the
whole reason this is a script and not a `cp`.

**Without it the program still builds and still runs.** `src/build.sh` puts a
zero-filled `NRL.BIN` on the disc instead, the head checks for `PUSH AF` at
`NRLLOAD+&0BB8` before hooking the rules, finds zeros, and says so on screen:
*"NRL.BIN was not loaded, so there is no prompt and only the sentence built in
here can be spoken."* The head still draws, still animates, still speaks its
built-in line.

## GPL-3: everything else

© 2026 Michael Wessel (LambdaMikel) and Claude, under the GPL-3 in
[`LICENSE`](LICENSE) — the same licence as LambdaSpeak.

| | |
|---|---|
| `src/head.asm`, `src/line.asm`, `src/headdata.inc` | the Z80 program |
| `src/mkhead.py`, `src/preview.py`, `src/build.sh`, `src/dist.sh` | the build |
| `tools/extract_nrl.sh`, `tools/reloc.asm` | getting the rules out of a driver you own |
| `tools/dz80.py`, `tools/walk.py`, `tools/mkwords.py`, `tools/nrlwords.asm` | the disassembler and the word harness |
| `emu/*.lua` | the emulator harnesses |
| `disk/HEAD.BIN`, `disk/head.dsk`, `disk/head.hfe` | built from the above, and checked to contain none of the driver |
| `README.md`, `docs/*.png` | the write-up and its screenshots |
| `original/` | Michael's 1985 BASIC and the digitised head data |

## Cited, not reproduced: Parke's head

The wireframe descends from F. I. Parke, *"Computer generated animation of
faces"*, ACM Annual Conference 1972
([doi:10.1145/800193.569955](https://dl.acm.org/doi/10.1145/800193.569955)).
**No figure from that paper and no frame of the film is reproduced here.** The
links go to the work itself. What is in `original/` is Michael's own 1985
digitisation, done by hand off a *P.M. Computerheft* article.

## Public domain: the rules themselves

The algorithm the driver implements is the **NRL letter-to-sound rules** —
Elovitz, Johnson, McHugh and Shore, *Automatic Translation of English Text to
Phonetics by Means of Letter-to-Sound Rules*, NRL Report 7948, 1976
([DTIC](https://apps.dtic.mil/sti/pdfs/ADA021929.pdf)). A work of the US
Government: **the rules are free to implement.** Only Amstrad's 1985
expression of them is not, which is the entire reason for the download.

A clean implementation — there are public-domain ones, including Wasser's 1985
C version — would remove the download too. That is planned for LambdaSpeak 4's
`|SAYSPO`, and this program could then use it instead.
