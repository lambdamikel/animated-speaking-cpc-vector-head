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
HEAD_LEN         equ #1DD3           ; 7635, from HEAD.BIN's own header
NRL_ORG          equ #2000
NRL_LEN          equ #1780           ; 6016, likewise

;; Above the head's last byte (#9DD2) and below AMSDOS's workspace (~#A700).
STUB_AT          equ #9E00

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
    ld hl,nrl_img                    ; the rules
    ld de,NRL_ORG
    ld bc,NRL_LEN
    ldir

    ld hl,head_img                   ; and the head
    ld de,HEAD_ORG
    ld bc,HEAD_LEN
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
    call KL_L_ROM_DISABLE            ; and so it can read the rules at #2000
    call HEAD_ORG
    call KL_L_ROM_ENABLE
    call KL_U_ROM_ENABLE
    ret
ramstub_end:

nrl_img:
    incbin "NRL.RAW"
head_img:
    incbin "HEAD.RAW"

    defs #4000-($-#C000),#FF         ; a ROM is 16 KB whether it needs to be

    save "VH.ROM",#C000,#4000
