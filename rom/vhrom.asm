;; The vector head as an Amstrad CPC expansion ROM.
;;
;; 16 KB, a background ROM providing one RSX, |VH. No disc, no loader, no
;; MEMORY statement: the two payloads the disc version loads -- the head
;; itself at #8000 and the 1985 NRL rules at #2000 -- travel in the ROM and
;; are copied into place by the RSX.
;;
;; Built for LambdaSpeak AI's ROM emulation, which answers upper-ROM reads
;; out of flash, so this needs no ROM board.
;;
;; Two builds. Without -DLSAI the ROM carries Amstrad's 1985 letter-to-sound
;; engine and runs on any CPC with any SP0256 card -- and is not
;; redistributable, because those 6016 bytes are not ours. With -DLSAI it
;; carries none of them and asks the card instead, through &E9, which answers
;; out of a clean implementation of the same Naval Research Laboratory rules.
;; That build is 6 KB smaller and can be published.
;;
;; Two things decide the shape of it.
;;
;; The head returns to BASIC rather than ending the program: start saves SP
;; and puts it back when the line editor quits. So the RSX CALLs it instead
;; of using MC START PROGRAM, which would reset the firmware.
;;
;; And the head reads screen memory -- "ldir ; screen -> buffer" in its
;; double-buffered blit -- which an expansion ROM cannot allow, because the
;; upper ROM shadows #C000 where the screen lives. Writes reach the RAM
;; underneath either way; reads would come back as ROM. The upper ROM
;; therefore has to be switched off while the head runs, and that cannot be
;; done by code running inside it: the instruction after the switch would be
;; fetched from RAM. Hence the stub, copied to RAM first and jumped to.
;;
;; The LOWER ROM has to go too, and that one is easy to miss. Both ROMs are
;; enabled while an RSX runs, and the rules live at #2000 -- inside the lower
;; ROM's shadow. The LDIR puts them there happily, because writes always reach
;; the RAM underneath, but the head reads a signature byte back to decide
;; whether the rules arrived, and with the lower ROM in the way it read the
;; operating system instead. The head ran, drew, and reported "NRL.BIN was not
;; loaded" while the rules sat in the RAM beneath it.
;;
;;     rasm vhrom.asm
;;
;; NRL.RAW and HEAD.RAW are the .BIN files with their 128-byte AMSDOS headers
;; removed. The rules are not redistributable -- see LICENSE-NOTE.md -- so
;; neither they nor the ROM built from them belong in this repository.

HEAD_ORG         equ #8000
NRL_ORG          equ #2000

;; The lengths are measured from the images themselves rather than written
;; down. They were constants taken from the .BIN headers, and correcting a
;; line of the credits grew the head by 36 bytes -- which a hard-coded #1DD3
;; would have copied short, silently, leaving the last 36 bytes of the program
;; as whatever was in RAM.

;; The stub goes immediately after the head, wherever that now ends.
;;
;; It was #9E00, chosen as "above the head's last byte, #9DD2". The head has
;; grown twice since -- a corrected credit line, then the port exchange that
;; replaces the 1985 engine -- and at 7718 bytes it reaches #9E66, so the stub
;; was being copied over its last hundred bytes and jumped to. Black screen.
;; Deriving it cannot go stale; the assert below catches the day it collides
;; with AMSDOS instead.

;; Measured, not looked up: #B906 is KL L ROM ENABLE, which fixes the order
;; of this block. The manuals' #BCCE is something else.
KL_U_ROM_ENABLE  equ #B900
KL_U_ROM_DISABLE equ #B903
KL_L_ROM_ENABLE  equ #B906
KL_L_ROM_DISABLE equ #B909

    org #C000

    db 1                             ; background ROM, so it offers an RSX
    db 0                             ; mark
    db 1                             ; version
    db 0                             ; modification
    dw names

    jp vh                            ; the one entry in the jump block

names:
    db "V"
    db "H"+#80                       ; the last character carries bit 7
    db 0                             ; and a zero ends the table

vh:
    ifndef LSAI
    ld hl,nrl_img                    ; the rules
    ld de,NRL_ORG
    ld bc,nrl_end-nrl_img
    ldir
    endif

    ld hl,head_img                   ; and the head
    ld de,HEAD_ORG
    ld bc,head_end-head_img
    ldir

    ld hl,ramstub                       ; and the three instructions that can
    ld de,STUB_AT                       ; turn this ROM off from outside it
    ld bc,ramstub_end-ramstub
    ldir
    jp STUB_AT

;; Runs from RAM. The RET goes back to whoever called the RSX, because the
;; jump above left that return address on the stack.
ramstub:
    call KL_U_ROM_DISABLE            ; so the head can read the screen
    call KL_L_ROM_DISABLE            ; and, in the classic build, the rules
    call HEAD_ORG
    call KL_L_ROM_ENABLE
    call KL_U_ROM_ENABLE
    ret
ramstub_end:

    ifndef LSAI
nrl_img:
    incbin "NRL.RAW"
nrl_end:
    endif
head_img:
    incbin "HEAD.RAW"
head_end:

STUB_AT          equ HEAD_ORG + (head_end-head_img)
AMSDOS_BASE      equ #A700                ; roughly where its workspace starts
    assert STUB_AT + (ramstub_end-ramstub) < AMSDOS_BASE

;; A ROM that does not fit is worth hearing about at build time.
    assert $-#C000 <= #4000

    defs #4000-($-#C000),#FF         ; a ROM is 16 KB whether it needs to be

    save "VH.ROM",#C000,#4000
