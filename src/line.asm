;; ---------------------------------------------------------------
;; VECTORHEAD/CPC - screen addressing and line drawing
;;
;; MODE 2: one bit per pixel, bit 7 leftmost, 80 bytes to a scanline,
;;     addr = #C000 + (y AND 7)*2048 + (y/8)*80 + x/8
;; The eight scanlines of a character cell are 2048 apart, so stepping
;; down a line is "add 8 to H" seven times out of eight, and on the
;; eighth it is one 16-bit add: +80 and -#4000, which is #C050.  That is
;; the whole reason this is fast - the address is never recomputed inside
;; a line, and neither is the pixel mask: it just rotates, and the byte
;; pointer moves when the rotation wraps.
;; ---------------------------------------------------------------

;; The two screen pages.  #C000 is where the firmware starts; #4000 is the
;; other one, and it has to be that one - #8000 would run into the
;; firmware's own workspace at #B100.  Which is why the program itself
;; lives at #8000 and not, as everything else on this machine does, at
;; #4000.
PAGE0   equ #C0
PAGE1   equ #40

    align 8
maskt:
    defb #80,#40,#20,#10,#08,#04,#02,#01

rowtab:
    defw 0,80,160,240,320,400,480,560,640,720,800,880,960,1040,1120
    defw 1200,1280,1360,1440,1520,1600,1680,1760,1840,1920

;; B = scanline 0..199, DE = x 0..639  ->  HL = byte address, C = pixel mask
scraddr:
    ld a,e
    and 7
    add a,maskt and 255         ; the mask from a table, not from rotating
    ld l,a                      ; #80 round the bit count - that loop was
    ld h,maskt/256              ; up to 64 us, once per segment
    ld c,(hl)
    ld a,e
    srl d
    rra
    srl d
    rra
    srl d
    rra                         ; DE/8: A = byte column 0..79, D = 0
    ld e,a
    ld a,b
    rrca
    rrca
    rrca
    and #1F                     ; y/8, the character row
    add a,a
    ld l,a
    ld h,0
    push de                     ; the byte column
    ld de,rowtab
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl                    ; HL = the row's offset
    pop de
    add hl,de
    ld a,b
    and 7                       ; (y AND 7)*2048 is *8 in the high byte
    add a,a
    add a,a
    add a,a
    add a,h
    ld h,a
    ld a,(drawbase)             ; whichever page is being drawn into
    add a,h
    ld h,a
    ret

;; HL one scanline down.  Seven times out of eight this is three bytes of
;; work; the eighth crosses into the next character row.
scrdown:
    ld a,h
    add a,8
    ld h,a
    and #38
    ret nz
    push de
    ld de,#C050                 ; +80 and -#4000, in one add
    add hl,de
    pop de
    ret

;; HL one scanline up
scrup:
    ld a,h
    sub 8
    ld h,a
    and #38
    cp #38
    ret nz
    push de
    ld de,#3FB0                 ; -80 and +#4000
    add hl,de
    pop de
    ret


;; ---------------------------------------------------------------
;; drawline - (lx0,ly0) to (lx1,ly1), x 0..639, y 0..199
;;
;; Bresenham, normalised so x always runs left to right, which leaves
;; only the y direction open.  Rather than test it per pixel - or call a
;; patched step routine, which is what the first version did and what
;; cost it 27 T a pixel in CALL and RET alone - there are four inner
;; loops, one per (major axis, y direction), each with the screen step
;; written into it.  The head is mostly near-vertical lines, so it is the
;; y-major loops that matter: there the step happens on every pixel.
;; ---------------------------------------------------------------
drawline:
    ld hl,(lx0)
    ld de,(lx1)
    or a
    sbc hl,de
    jr c,dl_ordered             ; x0 < x1
    jr z,dl_ordered
    ld hl,(lx0)                 ; swap the two endpoints
    ld de,(lx1)
    ld (lx0),de
    ld (lx1),hl
    ld a,(ly0)
    ld b,a
    ld a,(ly1)
    ld (ly0),a
    ld a,b
    ld (ly1),a
dl_ordered:
    ld hl,(lx1)
    ld de,(lx0)
    or a
    sbc hl,de
    ld a,l                      ; dx fits a byte: no segment of the head is
    ld (ldx),a                  ; wider than half of it
    ld a,(ly1)
    ld b,a
    ld a,(ly0)
    sub b                       ; y0 - y1: positive means up the screen
    jr nc,dl_up
    neg
    ld b,0                      ; down
    jr dl_dy
dl_up:
    ld b,1
dl_dy:
    ld (ldy),a
    ld a,b
    ld (ydir),a
    ld a,(ly0)
    ld b,a
    ld de,(lx0)
    call scraddr                ; HL = address, C = mask
    ld a,(ldy)
    ld b,a
    ld a,(ldx)
    cp b
    jr nc,dl_xmajor
;; y is the major axis - a step down or up on every pixel
    ld a,b
    ld (lmaj),a
    srl a
    ld d,a                      ; err = major/2
    ld a,(ldx)
    ld e,a                      ; minor
    inc b
    ld a,(ydir)
    or a
    jr nz,dl_yu
dl_yd:
    ld a,(hl)
    or c
    ld (hl),a
    ld a,h                      ; one scanline down
    add a,8
    ld h,a
    and #38
    jr nz,dl_yd2
    ld a,l                      ; ... and into the next character row
    add a,80
    ld l,a
    jr nc,$+3
    inc h
    ld a,h
    sub #40
    ld h,a
dl_yd2:
    ld a,d
    sub e
    ld d,a
    jr nc,dl_yd3
    ld a,(lmaj)
    add a,d
    ld d,a
    rrc c                       ; one pixel right
    jr nc,dl_yd3
    inc hl
dl_yd3:
    djnz dl_yd
    ret
dl_yu:
    ld a,(hl)
    or c
    ld (hl),a
    ld a,h                      ; one scanline up
    sub 8
    ld h,a
    and #38
    cp #38
    jr nz,dl_yu2
    ld a,l
    sub 80
    ld l,a
    jr nc,$+3
    dec h
    ld a,h
    add a,#40
    ld h,a
dl_yu2:
    ld a,d
    sub e
    ld d,a
    jr nc,dl_yu3
    ld a,(lmaj)
    add a,d
    ld d,a
    rrc c
    jr nc,dl_yu3
    inc hl
dl_yu3:
    djnz dl_yu
    ret
;; x is the major axis - the screen step is the rare case here
dl_xmajor:
    ld (lmaj),a
    ld b,a
    srl a
    ld d,a
    ld a,(ldy)
    ld e,a
    inc b
    ld a,(ydir)
    or a
    jr nz,dl_xu
dl_xd:
    ld a,(hl)
    or c
    ld (hl),a
    rrc c                       ; one pixel right
    jr nc,dl_xd2
    inc hl
dl_xd2:
    ld a,d
    sub e
    ld d,a
    jr nc,dl_xd3
    ld a,(lmaj)
    add a,d
    ld d,a
    ld a,h                      ; one scanline down
    add a,8
    ld h,a
    and #38
    jr nz,dl_xd3
    ld a,l
    add a,80
    ld l,a
    jr nc,$+3
    inc h
    ld a,h
    sub #40
    ld h,a
dl_xd3:
    djnz dl_xd
    ret
dl_xu:
    ld a,(hl)
    or c
    ld (hl),a
    rrc c
    jr nc,dl_xu2
    inc hl
dl_xu2:
    ld a,d
    sub e
    ld d,a
    jr nc,dl_xu3
    ld a,(lmaj)
    add a,d
    ld d,a
    ld a,h                      ; one scanline up
    sub 8
    ld h,a
    and #38
    cp #38
    jr nz,dl_xu3
    ld a,l
    sub 80
    ld l,a
    jr nc,$+3
    dec h
    ld a,h
    add a,#40
    ld h,a
dl_xu3:
    djnz dl_xu
    ret

lx0:    defw 0
lx1:    defw 0
ly0:    defb 0
ly1:    defb 0
ldx:    defb 0
ldy:    defb 0
lmaj:   defb 0
ydir:   defb 0
