;; Make a copy of the 1985 letter-to-sound engine that is fixed to OUR
;; address instead of relocating itself at run time: put the file at the
;; address it will live at, let its own relocator run once here, and take
;; the result away as a blob.
DRVBASE equ #0200               ; where the driver must end up fixed
DRVSRC  equ #4000               ; and where we are handed it, and hand it back
    org #8000
    jp start
start:
    ld hl,DRVSRC                ; the raw file, put there by the harness
    ld de,DRVBASE
    ld bc,6016
    ldir
    ld hl,(DRVBASE)             ; its entry offset, then relocate in place
    ld de,DRVBASE
    add hl,de
    xor a
    ld ix,0
    ld de,back
    push de
    jp (hl)
back:
    ld hl,DRVBASE               ; hand the relocated copy back above #4000,
    ld de,DRVSRC                ; where the emulator can actually read it:
    ld bc,6016                  ; below that it sees the lower ROM
    ldir
    ld a,#AA
    ld (#7FFF),a                ; done marker
    ret
tabend:
    save "RELOC.BIN", #8000, tabend-#8000, AMSDOS, start
