;; Convert a list of words with the 1985 rules and write down what they
;; became, so a respelling can be tried without listening to it.
NRL     equ #0200
NRLBASE equ NRL + #0AE0
CONVERT equ NRLBASE + #02BA     ; HL = text, B = length
QUEUE   equ NRLBASE + #00D8

    org #8000
    jp start

OUTBUF  equ #9000               ; indices, #FF between words, #FE at the end

outp:   defw OUTBUF
wordp:  defw 0
mark:   defb 0

start:
    ld hl,#2000
    ld de,NRL
    ld bc,6016
    ldir
    ld hl,QUEUE
    ld (hl),#C3
    inc hl
    ld (hl),capture and 255
    inc hl
    ld (hl),capture >> 8
    ld hl,OUTBUF
    ld (outp),hl
    ld a,#55                    ; got this far
    ld (mark),a
    ld hl,words                 ; the list pointer lives in memory: the
    ld (wordp),hl               ; engine is not known to preserve IX or IY
nw_next:
    ld hl,(wordp)
    ld a,(hl)
    or a
    jr z,nw_done
    ld b,a
    inc hl                      ; the text follows the length
    call CONVERT
    ld hl,(outp)                ; end of this word
    ld (hl),#FF
    inc hl
    ld (outp),hl
    ld hl,(wordp)               ; on to the next entry
    ld a,(hl)
    inc a
    ld e,a
    ld d,0
    add hl,de
    ld (wordp),hl
    jr nw_next
nw_done:
    ld hl,(outp)
    ld (hl),#FE
    ld a,#AA
    ld (mark),a
    ret

capture:
    push hl
    and #3F
    ld hl,(outp)
    ld (hl),a
    inc hl
    ld (outp),hl
    pop hl
    scf
    ret

    include "words.inc"

tabend:
    save "NRLWORDS.BIN", #8000, tabend-#8000, AMSDOS, start
