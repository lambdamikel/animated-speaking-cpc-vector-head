;; ---------------------------------------------------------------
;; VECTORHEAD/CPC - the vector head of P-C-S.BAS, in Z80
;; (C)2026 LAMBDAMIKEL + CLAUDE.  Assembles with rasm.
;;
;; The 1985/86 BASIC read the head out of DATA statements as *strings*,
;; ran VAL over every coordinate, scaled it with floating point and asked
;; the firmware to draw each line - twice, once per half, because only
;; half a face is digitised and the other half is x negated.  That is the
;; program this reproduces, with the same coordinates and the same
;; mirroring, but with the coordinates already in screen space and the
;; lines drawn straight into screen memory.
;;
;; The lips are taken out of that static head and drawn separately, from
;; ten viseme tables, so the face can mouth what the SP0256-AL2 says; the
;; eye is the same idea, three shapes of it, for blinking.
;;
;; Those redraws go to whichever screen page is not being looked at, and
;; the page is flipped when they are done - so a mouth is never caught
;; half drawn.  It also means the shapes can simply be painted over a
;; clean copy of the box they live in, instead of XORed away again, and
;; nothing can cancel anything.
;; ---------------------------------------------------------------

SCR_SET_MODE    equ #BC0E
SCR_SET_INK     equ #BC32
SCR_SET_BORDER  equ #BC38
TXT_OUTPUT      equ #BB5A
TXT_SET_CURSOR  equ #BB75       ; H = column, L = row, 1 based
TXT_GET_CURSOR  equ #BB78       ; ... and back again
TXT_CUR_OFF     equ #BB84
TXT_WIN_ENABLE  equ #BB66       ; H/D = the two columns, E/L = the two rows
TXT_CLEAR_WIN   equ #BB6C
KM_WAIT_CHAR    equ #BB06
TXT_CUR_ON      equ #BB81
KL_FIND_COMMAND equ #BCD1       ; HL = the name -> HL = routine, C = ROM.
                                ; #BCD4 is KL NEW FRAME FLY - that one
                                ; finds nothing, not even AMSDOS DISC
;; The 1985 driver is loaded here, low, where nothing else goes: at #2000
;; its own workspace sits just above its code and ran straight into the
;; second screen page at #4000, so the first mouth redraw destroyed it and
;; the machine reset the moment SAY was called.  Measured by patching its
;; allophone output and watching the counter stay at zero.
;; The 1985 driver goes here, and its phoneme buffer is at #9600 - a fixed
;; address, not one relative to where it is loaded (measured by watching
;; every write it makes).  So nothing of ours may live at #9600, which is
;; exactly where the eye's clean-box buffer used to be: the driver wrote
;; its phonemes over our buffer, our redraw wrote the screen back over its
;; phonemes, and the machine reset in the middle of SAY.
;; The 1985 letter-to-sound engine, as a subroutine rather than a driver.
;;
;; NRL.BIN is the SSA-1 driver's own code, already relocated for #0200 and
;; with the flag that says "my interrupt ticker is running" cleared.  None
;; of the driver is started: no init, no RSX, no ticker - only the rules
;; are wanted.  The routine that used to hand an allophone to the chip's
;; queue is redirected into sayhook, so converting a sentence is an
;; ordinary CALL that returns with the allophones written down, and they
;; are spoken afterwards by the loop that speaks the opening sentence,
;; with the mouth on them.
;;
;; The rules are the Naval Research Laboratory's, as shipped in 1985.
NRLLOAD         equ #2000       ; where the loader drops the file
NRL             equ #0200       ; where it runs from
NRLBASE         equ NRL + #0AE0 ; the engine's own addresses count from here
CONVERT         equ NRLBASE + #02BA      ; HL = text, B = length
NRLQUEUE        equ NRLBASE + #00D8      ; its output, redirected to us
NRLLEN          equ 6016
SSA1            equ #FBEE       ; the Amstrad SSA-1's port, and LambdaSpeak's
KL_TIME_PLEASE  equ #BD0D       ; DEHL = the 1/300 s tick count
SCR_SET_BASE    equ #BC08       ; A = the page, #C0 or #40
CAS_IN_OPEN     equ #BC77       ; B = name length, HL = name, DE = 2K buffer
CAS_IN_DIRECT   equ #BC83       ; HL = where to put it
CAS_IN_CLOSE    equ #BC7A
TXT_VDU_DISABLE equ #BB57
TXT_VDU_ENABLE  equ #BB54

    ;; #4000 is the second screen page now, so the program moves up to
    ;; #8000 - still clear of AMSDOS's workspace, which starts about
    ;; #A700, and well clear of the lower ROM's shadow below #4000
    org #8000
    jp start                    ; RUN" enters at the load address

    include "line.asm"
    include "headdata.inc"      ; before the code: the mirror blit needs
                                ; revtab's address while it is unrolled

start:
    ld (spsave),sp              ; quitting happens from inside the line
                                ; editor, several calls deep; the stack
                                ; has to be put back before returning to
                                ; BASIC or the RET lands in our own code
    ld a,2
    call SCR_SET_MODE
    call TXT_CUR_OFF
    ld bc,0
    call SCR_SET_BORDER
    xor a
    ld bc,0
    call SCR_SET_INK
    ld a,1
    ld bc,#1A1A
    call SCR_SET_INK
    call cls
    call installnrl             ; the rules, if the loader brought them
    call setspeed
restart:
    call cls                    ; the prompt off the screen before the head
    call KL_TIME_PLEASE         ; time the head, it is the whole point
    ld (t0),hl
    call drawhead
    call KL_TIME_PLEASE
    ld de,(t0)
    or a
    sbc hl,de
    ld (ticks),hl

    call spdetect               ; the driver was installed before the head
    ld hl,mouthbox              ; went up: doing it twice re-relocates code
                                ; that is already relocated, and the mouth
                                ; and eyes never appear again              ; with the head drawn and nothing else in
    call setbox                 ; them, the two boxes are worth keeping:
    call savebox                ; restoring one is how a shape gets wiped
    ld hl,eyebox
    call setbox
    call savebox
    call maskint
    ld a,REST                   ; now the shapes themselves, over the top
    ld (curvis),a
    ld hl,mouthtab
    call drawshape
    call mirrormouth
    xor a
    ld (cureye),a
    ld hl,eyetab
    call drawshape
    call mirroreyes
    call unmaskint
    ld a,(viewbase)             ; from here on, drawing goes to the page
    xor PAGE0 xor PAGE1         ; that is not on show...
    ld (drawbase),a
    call syncpages              ; ... which first gets a copy of this one
    ld h,WINLEFT                ; and the right of the screen becomes a
    ld d,79                     ; text window: the head lives on the left
    ld l,0                      ; now, clear of it
    ld e,24
    call TXT_WIN_ENABLE
    call winhome
    ld hl,abouttxt              ; the credits, to read while it talks
    call wrapz
    call syncpages              ; on both pages, or the first flip of the
                                ; mouth would take them away again
    ld a,(hooked)               ; Without the engine there is no prompt and
    or a                        ; only the one sentence built in, and that
    jr nz,sp_again              ; looked exactly like the program hanging:
    ld hl,nonrltxt              ; a key repeats the sentence and nothing
    call wrapz                  ; else ever happens.  Say so.
    call syncpages
sp_again:
    call speakintro
    ld a,(firstrun)             ; the credits are on screen: give them a
    or a                        ; chance to be read before the prompt
    jr z,sp_loop
    xor a
    ld (firstrun),a
    ld hl,anykeytxt
    call wrapz
    call syncpages
    call KM_WAIT_CHAR
sp_loop:
    ld a,(hooked)
    or a
    jr z,sp_key                 ; no rules loaded: just the keys
    call askline                ; then ask for another, and another
    ld a,(saylen)
    or a
    jp z,sp_loop                ; nothing typed: just ask again.  This used
                                ; to say the intro over, and a key held down
                                ; at "Press any key" repeats, so the repeat
                                ; arrived here as an empty line and started
                                ; the intro again - there was no way out.
    cp 1
    jr nz,sp_say0
    ld a,(saybuf)               ; a lone , or . is the speed, not a word
    cp ','
    jp z,sp_faster              ; those live far enough away to need JP
    cp '<'
    jp z,sp_faster
    cp '+'
    jp z,sp_faster
    cp '.'
    jp z,sp_slower
    cp '>'
    jp z,sp_slower
    cp '-'
    jp z,sp_slower
sp_say0:
    ld a,(saylen)               ; QUIT on its own leaves
    cp 4
    jr nz,sp_say
    ld hl,saybuf
    ld de,quitword
    ld b,4
sq_cmp:
    ld a,(de)
    cp (hl)
    jr nz,sp_say
    inc hl
    inc de
    djnz sq_cmp
    jp sp_quit
sp_say:
    call fixwords
    call saywords
    call listphon               ; what the rules made of it
    call syncpages              ; the text went to the page on show only
    ld hl,phonbuf
    call speakfrom
    ld hl,anykeytxt             ; what the rules made of it stays up until
    call wrapz                  ; it has been read
    call syncpages
    call KM_WAIT_CHAR
    jp sp_loop
sp_key:
    call KM_WAIT_CHAR
    cp ' '
    jp z,sp_again               ; SPACE says it again
    cp 's'
    jr z,sp_ls
    cp 'S'
    jr z,sp_ls
    cp 27                       ; only ESC and Q leave: anything else, and
    jr z,sp_quit                ; a stray keypress - the ENTER that ended
    cp 'q'                      ; the prompt, say - would throw the head
    jr z,sp_quit                ; away
    cp 'Q'
    jr nz,sp_key
sp_quit:
    ;; There is nothing to go back to: the letter-to-sound engine was
    ;; copied to #0200, which is where BASIC keeps the program that
    ;; started us, so returning would run whatever the engine's bytes
    ;; happen to look like to BASIC.  A firmware restart is the honest
    ;; way out - it puts the mode, the screen and BASIC back properly.
    jp #0000

sp_ls:
    ld bc,SSA1                  ; LambdaSpeak wakes up emulating the SSA-1
    ld a,#E2                    ; with DECtalk; &E2 puts it on its own
    out (c),a                   ; SP0256-AL2, which is the real voice.  A
    call spdetect               ; genuine SSA-1 shrugs this off as one more
    jr sp_key                   ; allophone byte



cls:
    ld a,(drawbase)
    ld h,a
    ld l,0
    ld d,h
    ld e,1
    ld bc,#3FFF
    ld (hl),0
    ldir
    ret

;; ---------------------------------------------------------------
;; two screen pages
;;
;; Everything is drawn into the page that is not on show, and the flip
;; happens between frames, so a redraw is never visible in progress.  The
;; page that comes back into view a moment later still holds the shape
;; from before last, which is why every redraw starts by putting the
;; clean box back.
;; ---------------------------------------------------------------
flip:
    ld a,(drawbase)
    ld (viewbase),a
    call SCR_SET_BASE           ; the CRTC picks this up at the next frame
    ld a,(viewbase)
    xor PAGE0 xor PAGE1         ; #C0 <-> #40
    ld (drawbase),a
    ret

;; the page on show, copied over the other one
syncpages:
    ld a,(viewbase)
    ld h,a
    ld l,0
    ld a,(drawbase)
    ld d,a
    ld e,0
    ld bc,#4000
    ldir
    ret

;; ---------------------------------------------------------------
;; the boxes the moving parts live in
;;
;; A descriptor is column, width, first scanline, scanlines, and where the
;; clean copy of that rectangle is kept.
;; ---------------------------------------------------------------
mouthbox: defb MOUTHCOL,MOUTHCOLW,MOUTHROW,MOUTHROWS
          defw mouthbuf
eyebox:   defb EYECOL,EYECOLW,EYEROW,EYEROWS
          defw eyebuf

setbox:
    ld a,(hl)
    ld (bcol),a
    inc hl
    ld a,(hl)
    ld (bw),a
    inc hl
    ld a,(hl)
    ld (brow),a
    inc hl
    ld a,(hl)
    ld (brows),a
    inc hl
    ld a,(hl)
    ld (bbuf),a
    inc hl
    ld a,(hl)
    ld (bbuf+1),a
    ret

;; HL = where the box starts on the page being drawn into
boxaddr:
    ld a,(bcol)
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl                   ; column to pixel
    ex de,hl
    ld a,(brow)
    ld b,a
    jp scraddr

savebox:
    call boxaddr
    ld de,(bbuf)
    ld a,(brows)
    ld b,a
sv_row:
    push bc
    ld a,(bw)
    ld c,a
    ld b,0
    push hl
    ldir                        ; screen -> buffer, the buffer running on
    pop hl
    call scrdown
    pop bc
    djnz sv_row
    ret

restorebox:
    call boxaddr
    ex de,hl                    ; DE = screen
    ld hl,(bbuf)
    ld a,(brows)
    ld b,a
rs_row:
    push bc
    ld a,(bw)
    ld c,a
    ld b,0
    push de                     ; the row's start on screen
    ldir                        ; buffer -> screen
    ex (sp),hl                  ; HL = that row's start, buffer on the stack
    call scrdown
    ex de,hl                    ; DE = the next row
    pop hl                      ; ... and HL is the buffer again
    pop bc
    djnz rs_row
    ret

;; ---------------------------------------------------------------
;; the head: the digitised half, then the same half mirrored
;; ---------------------------------------------------------------
;; Only the left half is drawn.  The other half is the same bytes with the
;; bits in the opposite order, so it is a blit and not a second pass of
;; Bresenham: 19 bytes a scanline through a bit-reversal table, instead of
;; 3826 pixels of line drawing.  The mirror axis is 639-x, which is a byte
;; boundary - that is why the half is drawn at 319-dx and not 320-dx, and
;; it puts the centre line of the face half a pixel off where the BASIC
;; had it.  At 640 pixels across, that is not a thing anyone can see.
drawhead:
    call maskint                ; the speech driver's ticker runs from the
    call drawside               ; interrupt and does not put every register
    call mirrorhalf             ; back; a head drawn through it comes out
    jp unmaskint                ; in pieces

;; Masked only when the driver is loaded - without it there is nothing to
;; hide from, and the 1/300 s clock keeps running, which is what times the
;; drawing.
maskint:
    ld a,(usedi)
    or a
    ret z
    di
    ret

unmaskint:
    ld a,(usedi)
    or a
    ret z
    ei
    ret
;; one side: walk the polyline table, drawing vertex to vertex
drawside:
    ld hl,head
    ld (tabptr),hl
;; (tabptr) = a polyline table: count, (dx,scanline) pairs, ... , 0
;;
;; The walker used to keep this pointer in IX, which cost nothing until
;; the speech driver was installed: its interrupt routine uses IX and does
;; not put it back, so the head drew itself into nonsense halfway through.
;; A pointer in memory cannot be taken away.
drawtable:
ds_poly:
    ld hl,(tabptr)
    ld a,(hl)
    or a
    ret z                       ; a zero count ends the table
    ld b,a
    inc hl
    ld (tabptr),hl
    call ds_fetch               ; the first vertex is only a move
    dec b
    jr z,ds_poly
ds_seg:
    ld hl,(curx)                ; the previous vertex...
    ld (lx0),hl
    ld a,(cury)
    ld (ly0),a
    call ds_fetch               ; ... to this one
    push bc
    call drawline
    pop bc
    djnz ds_seg
    jr ds_poly

;; (IX) = dx from the centre, scanline -> the line's second endpoint, and
;; the running "current vertex" that the next segment starts from.  Kept
;; separate from lx1/ly1 because drawline may swap its own endpoints.
ds_fetch:
    push bc
    ld hl,(tabptr)
    ld e,(hl)
    inc hl
    ld a,(hl)
    inc hl
    ld (tabptr),hl
    ld (ly1),a
    ld (cury),a
    ld d,0
    ld hl,HEADX                 ; the BASIC had ORIGIN 320,0; the head sits
                                ; left of that now, to leave room for text
    or a
    sbc hl,de
    ld (lx1),hl
    ld (curx),hl
    pop bc
    ret

;; ---------------------------------------------------------------
;; the mouth
;;
;; The lips are not part of the static head - they are drawn from one of
;; ten viseme tables, in XOR, so that drawing the old shape a second time
;; rubs it out and leaves the static lines that cross the mouth alone.
;; Only the mouth's own box is mirrored afterwards, 7 bytes on 18
;; scanlines instead of the whole face.
;; ---------------------------------------------------------------
WINLEFT equ 41                  ; the text window's first column
WINROWS equ 25                  ; the window is the full height of the screen
SAYMAX  equ 96                  ; the longest line worth typing: any more
                                ; and the allophones run off the window
SAYBUFLEN equ 128               ; what was typed
FIXBUFLEN equ 176               ; and the same after the exception table,
FIXMAX  equ FIXBUFLEN-16        ; which can make it longer
WINW    equ 38                  ; ... and how much of it to fill: one
                                ; short of the edge, so the firmware never
                                ; wraps a line itself on top of our own

REST    equ 0                   ; the order in mkhead.py's VISEMES
COLM    equ MOUTHCOL            ; the box the lips move in - generated with
COLMW   equ MOUTHCOLW           ; the visemes, so widening a shape cannot
ROWM    equ MOUTHROW            ; leave half of it unmirrored
ROWMH   equ MOUTHROWS

;; A = shape index, HL = the group's table of shape pointers
drawshape:
    add a,a
    ld e,a
    ld d,0
    add hl,de
    ld a,(hl)
    inc hl
    ld h,(hl)
    ld l,a
    ld (tabptr),hl
    jp drawtable

;; A = the viseme to show
setmouth:
    ld hl,curvis
    cp (hl)
    ret z                       ; already showing - most allophones in a
    ld (hl),a                   ; row want the same shape
    call KL_TIME_PLEASE         ; how long one shape change costs, because
    ld (t1),hl                  ; that is what limits how fast it can talk
    call update
    call KL_TIME_PLEASE
    ld de,(t1)
    or a
    sbc hl,de
    ld de,(mouthmax)
    or a
    sbc hl,de
    ret c
    add hl,de
    ld (mouthmax),hl
    ret

mirrormouth:
    ld b,ROWM
    ld de,COLM*8
    call scraddr                ; once, and then one scanline at a time:
    ld b,ROWMH                  ; working the address out per row cost a
mm_row:                         ; quarter of the blit
    push bc
    push hl
    ld d,h
    ld e,l
    ld a,e
    add a,MIRRORC-2*COLM             ; the mirror of this row's first column
    ld e,a
    jr nc,mm_go
    inc d
mm_go:
    ld b,h
    ld c,l
    ld h,revtab/256
    repeat COLMW
    ld a,(bc)
    ld l,a
    ld a,(hl)
    ld (de),a
    inc bc
    dec de
    rend
    pop hl
    call scrdown
    pop bc
    djnz mm_row
    ret

;; A = eye shape, 0 open .. 2 shut
seteye:
    ld hl,cureye
    cp (hl)
    ret z
    ld (hl),a
    jp update

;; ---------------------------------------------------------------
;; update - bring the page nobody is looking at up to date and show it
;;
;; Both moving parts, not just the one that changed.  The hidden page is
;; two flips behind, so after a blink it still has a half-shut eye on it,
;; and flipping to it for the next mouth shape would blink the eye again
;; - which is exactly what it looked like: a head that blinks its way
;; through a sentence.  What each page is currently showing is written
;; down per page, so only what is actually stale gets redrawn.
;; ---------------------------------------------------------------
pageptr:                        ; HL -> what the page being drawn shows
    ld hl,pstate
    ld a,(drawbase)
    cp PAGE0
    ret z
    inc hl
    inc hl
    ret

update:
    call maskint                ; same reason as drawhead
    call pageptr
    push hl
    ld a,(curvis)
    cp (hl)
    jr z,up_eye
    ld (hl),a
    ld hl,mouthbox
    call setbox
    call restorebox
    ld a,(curvis)
    ld hl,mouthtab
    call drawshape
    call mirrormouth
up_eye:
    pop hl
    inc hl
    ld a,(cureye)
    cp (hl)
    jr z,up_show
    ld (hl),a
    ld hl,eyebox
    call setbox
    call restorebox
    ld a,(cureye)
    ld hl,eyetab
    call drawshape
    call mirroreyes
up_show:
    call flip
    jp unmaskint

;; A blink, one step per call: half shut, shut, half, open.  People blink
;; two or three times in a sentence this long, and they do it while they
;; are talking - so the steps are taken in the gaps where the chip is
;; busy saying an allophone, and the speech is never held up for them.
blinktick:
    ld a,(blinkphase)
    or a
    ret z
    ld e,a
    ld d,0
    ld hl,blinkseq-1
    add hl,de
    ld a,(hl)
    push af
    ld a,(blinkphase)
    inc a
    cp 5
    jr c,bt_keep
    xor a                       ; that was the last step
bt_keep:
    ld (blinkphase),a
    pop af
    jp seteye

blinkseq: defb 1,2,1,0
;; The chip's allophones are a fixed length, so the only thing speech
;; speed can mean here is how much of the silence between words is kept.
;; Three settings, chosen by typing + or - at the prompt.
pausemap: defw pfast
;; Measured on one sentence of 38 allophones: with the three maps only a
;; step apart, quick and medium came out 3.0 s and 3.2 s - no difference
;; worth a key.  Spread across 10, 50 and 200 ms a word gap instead.
pslow:    defb 0,2,4,4,4        ; 200 ms between words
pmid:     defb 0,1,3,3,4        ; 100 ms
pfast:    defb 0,0,1,3,4        ; 30 ms - quick, but the words still part
                                ; PA4 and PA5 are full stops either way
;; That 30 ms was 10 ms, and 10 ms is not a gap: "I LIV IN THE C P C" came
;; out as one run of sound with no word in it that could be picked out.
;; Quick is meant to be quick, not slurred - and quick is what it starts on.
;; Raising it put quick 0.7 s from medium, though, which is the complaint the
;; three settings were spread out to answer in the first place, so medium
;; moved up to 100 ms to keep the steps worth a key: measured over the whole
;; intro, 19.1 / 21.3 / 24.6 seconds.
speed:    defb 2                ; 0 slow, 1 middling, 2 quick
blinkat:  defb 12,30,48,0       ; the allophones to start one on

;; the same blit as the mouth's, over the eye's box
mirroreyes:
    ld b,EYEROW
    ld de,EYECOL*8
    call scraddr
    ld b,EYEROWS
me_row:
    push bc
    push hl
    ld d,h
    ld e,l
    ld a,e
    add a,MIRRORC-2*EYECOL
    ld e,a
    jr nc,me_go
    inc d
me_go:
    ld b,h
    ld c,l
    ld h,revtab/256
    repeat EYECOLW
    ld a,(bc)
    ld l,a
    ld a,(hl)
    ld (de),a
    inc bc
    dec de
    rend
    pop hl
    call scrdown
    pop bc
    djnz me_row
    ret

;; ---------------------------------------------------------------
;; saying whatever gets typed in
;;
;; The 1985 SSA-1 driver has the Navy letter-to-sound rules in it and an
;; RSX called SAY, so there is no reason to write that again.  It is
;; loaded at #2000 before this program starts, and one instruction of it
;; is redirected here: where it masked the allophone and handed it to the
;; chip, it now calls this, which does the same and moves the mouth on
;; the way past.  So the mouth is driven by the phonemes the 1985 rules
;; produced, not by a guess at the timing.
;;
;; The routine being replaced is the driver's "queue one allophone":
;;     E5 C5 CD D8 00 30 FB C1 E1 C9
;;     push hl / push bc / call the queue / retry while full / ret
;; Jumping away from its first byte means the text is converted and the
;; allophones land here instead of in the chip's queue - which is fed
;; from an interrupt, and drawing a mouth from an interrupt is what was
;; resetting the machine.

;; Copy the engine down to where it was relocated for, and point its
;; output at us.  Nothing of the driver is started - no init, no RSX, no
;; interrupt ticker; only the rules are wanted.
installnrl:
    ld a,(NRLLOAD + #0BB8)      ; is it really loaded?  That offset is the
    cp #F5                      ; queue routine, and it starts with PUSH AF
    ret nz
    ld hl,NRLLOAD
    ld de,NRL
    ld bc,NRLLEN
    ldir
    ld hl,NRLQUEUE              ; its allophones come here instead
    ld (hl),#C3
    inc hl
    ld (hl),(sayhook) and 255
    inc hl
    ld (hl),(sayhook) >> 8
    ld a,1
    ld (hooked),a
    ret

;; A = an allophone, straight out of the 1985 rules.  The caller retries
;; while carry is clear, so say yes.
sayhook:
    push hl
    push de
    and #3F
    ld hl,(saytail)
    ld de,sayend
    ex de,hl
    or a
    sbc hl,de
    jr z,sh_full                ; buffer full: drop the rest
    ex de,hl
    ld (hl),a
    inc hl
    ld (saytail),hl
sh_full:
    pop de
    pop hl
    scf
    ret


;; ---------------------------------------------------------------
;; asking, and converting what was typed
;; ---------------------------------------------------------------
;; HL = text, printed into the window with the lines broken between
;; words rather than wherever the edge happens to fall.  A 13 in the text
;; is an explicit break.
wrapz:
    ld c,0                      ; the column reached so far
wz_next:
    ld a,(hl)
    or a
    ret z
    cp 13
    jr z,wz_break
    cp ' '
    jr nz,wz_meas
    inc hl                      ; a space, unless the line is full
    ld a,c
    or a
    jr z,wz_next
    cp WINW
    jr nc,wz_next
    inc c
    ld a,' '
    call wz_char
    jr wz_next
wz_break:
    inc hl
    call wz_nl
    jr wz_next
wz_meas:
    push hl                     ; how long is the word about to be printed?
    ld b,0
wz_m1:
    ld a,(hl)
    or a
    jr z,wz_m2
    cp ' '
    jr z,wz_m2
    cp 13
    jr z,wz_m2
    inc b
    inc hl
    jr wz_m1
wz_m2:
    pop hl
    ld a,c                      ; does it still fit on this line?
    add a,b
    cp WINW+1
    jr c,wz_put
    call wz_nl
wz_put:
    ld a,(hl)
    or a
    ret z
    cp ' '
    jr z,wz_next
    cp 13
    jr z,wz_next
    inc hl
    inc c
    call wz_char
    jr wz_put

wz_char:
    push hl
    push bc
    call TXT_OUTPUT
    pop bc
    pop hl
    ret

wz_nl:
    push hl
    push bc
    call newline
    pop bc
    pop hl
    ld c,0
    ret

sp_faster:
    ld a,(speed)
    cp 2
    jr nc,sp_shows
    inc a
    jr sp_setsp
sp_slower:
    ld a,(speed)
    or a
    jr z,sp_shows
    dec a
sp_setsp:
    ld (speed),a
    call setspeed
sp_shows:
    jp sp_loop                  ; the next prompt shows where it stands

setspeed:
    ld a,(speed)
    ld hl,pslow
    or a
    jr z,ss_put
    ld hl,pmid
    dec a
    jr z,ss_put
    ld hl,pfast
ss_put:
    ld (pausemap),hl
    ret

speedtxt: defb "Speed: ",0
quitword: defb "QUIT"
;; Eight bytes each, because the lookup multiplies by eight.  "middling"
;; was nine with its terminator, which pushed "quick" out of line and
;; printed nothing at all.
speedn:   defb "slow",0,0,0,0
          defb "medium",0,0
          defb "quick",0,0,0

;; The rules are the 1976 ones and have no exception dictionary, so the
;; words they get wrong are spelled here the way they have to sound.  Every
;; one of these was measured rather than guessed: run_words.sh puts a list
;; through the engine on the emulated machine and prints the allophones it
;; produced, so a respelling is tried and kept only if it comes out right.
;;
;; An entry is the word's length, the replacement's length, the word, and
;; what to say instead.  The two need not be the same length - DIGITIZED
;; only comes out right as eleven characters - so the line is rebuilt a
;; word at a time into fixbuf instead of being patched where it stands.
fixwords:
    ld a,(saylen)               ; terminate it, so the scan knows to stop
    ld e,a
    ld d,0
    ld hl,saybuf
    add hl,de
    ld (hl),0
    ld hl,saybuf
    ld de,fixbuf
fx_word:
    push hl                     ; never write past the end of what is built
    ld hl,fixbuf+FIXMAX
    or a
    sbc hl,de
    pop hl
    jp z,fx_end
    jp c,fx_end
    ld a,(hl)
    or a
    jp z,fx_end
    call isletter
    jr c,fx_look
    ld (de),a                   ; what is between words goes straight out,
    inc hl                      ; so a word with a full stop after it is
    inc de                      ; still that word - which it was not when
    jr fx_word                  ; only a space ended one, and HEY. went
fx_look:                        ; through untouched
    push hl                     ; HL = a word: how long is it?
    ld c,0
fx_len:
    ld a,(hl)
    call isletter
    jr nc,fx_gotlen
    inc hl
    inc c
    jr fx_len
fx_gotlen:
    ld a,c
    ld (fxlen),a
    pop hl
    ld ix,fixtab
fx_entry:
    ld a,(ix+0)
    or a
    jr z,fx_copy                ; not in the table: as it was typed
    ld c,a
    ld a,(fxlen)
    cp c
    jr nz,fx_next
    push hl
    push ix
    ld b,c
    inc ix                      ; the word follows the two lengths
    inc ix
fx_cmp:
    ld a,(ix+0)
    cp (hl)
    jr nz,fx_nomatch
    inc ix
    inc hl
    djnz fx_cmp
    pop ix
    pop hl
    jr fx_hit
fx_nomatch:
    pop ix
    pop hl
fx_next:
    ld a,(ix+0)                 ; on to the next entry
    add a,(ix+1)
    add a,2
    ld c,a
    ld b,0
    add ix,bc
    jr fx_entry

fx_hit:
    push hl                     ; the replacement goes out instead
    ld a,(ix+0)
    add a,2
    ld c,a
    ld b,0
    push ix
    pop hl
    add hl,bc                   ; HL = what to say
    ld b,(ix+1)
fx_h1:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz fx_h1
    pop hl
    ld a,(fxlen)                ; and the typed word is stepped over
    ld c,a
    ld b,0
    add hl,bc
    jp fx_word

fx_copy:
    ld a,(fxlen)
    ld b,a
fx_c1:
    ld a,(hl)
    ld (de),a
    inc hl
    inc de
    djnz fx_c1
    jp fx_word

fx_end:
    xor a
    ld (de),a
    ld hl,fixbuf                ; back where the rules will read it, at
    ld de,saybuf                ; whatever length it became
    ld c,0
fx_back:
    ld a,(hl)
    ld (de),a
    or a
    jr z,fx_done
    inc hl
    inc de
    inc c
    jr fx_back
fx_done:
    ld a,c
    ld (saylen),a
    ret

;; A = a character; carry set if it belongs to a word.  The prompt has
;; already put everything into capitals.
isletter:
    cp 'A'
    jr c,il_no
    cp 'Z'+1
    jr nc,il_no
    scf
    ret
il_no:
    or a                        ; and carry clear for everything else
    ret

;;       word           what to say instead
fixtab:
    defb 4,3,"HEAD","HED"
    defb 4,3,"LIVE","LIV"
    defb 2,2,"HI","HY"                    ; "hih", without the fix
    defb 4,5,"HIYA","HY YA"
    defb 3,3,"HEY","HAI"
    defb 2,3,"OH","OWE"
    defb 3,2,"BYE","BY"
    defb 7,6,"GOODBYE","GUD BY"
    defb 7,5,"BROUGHT","BRAUT"
    defb 9,11,"DIGITIZED","DIJJI TIZED"
    defb 8,10,"DIGITIZE","DIJJI TIZE"
    defb 7,8,"DIGITAL","DIJJITUL"
    defb 5,6,"DIGIT","DIJJIT"
    defb 4,3,"SAID","SED"
    defb 4,3,"SAYS","SEZ"
    defb 4,3,"DOES","DUZ"
    defb 6,6,"MOTHER","MUTHER"
    defb 3,3,"WHO","HOO"
    defb 7,7,"MACHINE","MUSHEEN"
    defb 6,5,"FRIEND","FREND"
    defb 5,5,"AGAIN","UGGEN"
    defb 5,5,"GREAT","GRAYT"
    defb 5,4,"HEART","HART"
    defb 5,5,"BUILD","BILLD"
    defb 4,5,"BUSY","BIZZY"
    defb 6,5,"PEOPLE","PEEPL"
    defb 5,6,"WOMEN","WIMMIN"
    defb 4,4,"ONCE","WUNS"
    defb 5,4,"WHERE","WAIR"
    defb 7,5,"THOUGHT","THAUT"
    defb 7,5,"THROUGH","THROO"
    defb 6,5,"ENOUGH","INUFF"
    defb 5,3,"LAUGH","LAF"
    defb 7,5,"MICHAEL","MIKEL"
    defb 9,7,"SCHNEIDER","SHNYDER"
    defb 0

winhome:
    ld h,1                      ; the corner of the window, not the screen
    ld l,1
    jp TXT_SET_CURSOR

;; A CR/LF pair through TXT OUTPUT does not reliably cost a row: two of
;; them in a row came out as one line break, so a blank line asked for
;; between two printed lines never appeared.  Asking the firmware where
;; the cursor is and putting it one row lower is exact, and it also gets
;; the row right after a typed line that ran past the window's edge.
newline:
    call TXT_GET_CURSOR         ; H = column, L = row, 1 based and
    ld h,1                      ; relative to the window
    inc l
    ld a,l
    cp WINROWS+1
    jr nc,nl_scroll             ; past the last row: the firmware still
    jp TXT_SET_CURSOR           ; has to scroll it
nl_scroll:
    ld a,13
    call TXT_OUTPUT
    ld a,10
    jp TXT_OUTPUT

askline:
    ld a,(noclear)              ; each exchange starts at the top of the
    or a                        ; window rather than scrolling it: the
    jr nz,al_keep
    call TXT_CLEAR_WIN
    call winhome
al_keep:
    xor a
    ld (noclear),a
    ld hl,speedtxt              ; where the speed stands, every time, so
    call wrapz                  ; it is never a message that vanishes
    ld hl,speedn
    ld a,(speed)
    add a,a
    add a,a
    add a,a
    ld e,a
    ld d,0
    add hl,de
    call putz                   ; short fixed lines: printed as they are,
    ld hl,hint1                 ; not through the wrapper, which trims the
    call putz                   ; spaces at a line's start and counts its
    call newline                ; own columns
    call newline
    ld hl,hint2
    call putz
    call newline
    call newline
    jp prompt                   ; and the firmware scrolls a window this
                                ; firmware scrolls a window this tall by
                                ; moving the hardware display offset, and
                                ; that slides the head with it

;; print a zero-terminated string
putz:
    ld a,(hl)
    or a
    ret z
    inc hl
    push hl
    call TXT_OUTPUT
    pop hl
    jr putz

;; the allophones of the sentence just typed, by name, underneath it
listphon:
    call newline
    call newline
    ld a,9
    ld (lpcount),a
    ld hl,phonbuf
lp_next:
    ld a,(hl)
    inc a
    ret z                       ; #FF ends them
    dec a
    push hl
    ld e,a                      ; three characters each, in the table the
    ld d,0                      ; generator writes out
    ld hl,phnames
    add hl,de
    add hl,de
    add hl,de
    ld b,3
lp_char:
    ld a,(hl)
    push hl
    push bc
    call TXT_OUTPUT
    pop bc
    pop hl
    inc hl
    djnz lp_char
    ld a,' '
    call TXT_OUTPUT
    pop hl
    inc hl
    push hl                     ; nine names to a line: four columns each
    ld hl,lpcount               ; against a window 39 wide, so a name is
    dec (hl)                    ; never split across the edge
    jr nz,lp_ok
    ld (hl),9
    call newline
    call TXT_GET_CURSOR         ; a very long sentence would scroll the
    ld a,l                      ; window, which takes the head with it:
    cp WINROWS-2                ; stop, and say that it was cut
    jr c,lp_ok
    pop hl
    ld hl,moretxt
    jp putz
lp_ok:
    pop hl
    jr lp_next

;; read a line into saybuf, echoed where the cursor stands
prompt:
    ld hl,asktxt
    call putz
    call TXT_CUR_ON
    ld hl,saybuf
    ld b,0
pr_key:
    call KM_WAIT_CHAR
    cp 27                       ; ESC gets out from here as well
    jp z,sp_quit
    cp 13
    jr z,pr_done
    cp 127                      ; DEL
    jr nz,pr_char
    ld a,b
    or a
    jr z,pr_key
    dec b
    dec hl
    ld a,8
    call TXT_OUTPUT
    ld a,' '
    call TXT_OUTPUT
    ld a,8
    call TXT_OUTPUT
    jr pr_key
pr_char:
    cp ' '
    jr c,pr_key
    cp 128
    jr nc,pr_key
    cp 'a'                      ; the rules work in capitals
    jr c,pr_up
    cp 'z'+1
    jr nc,pr_up
    and #DF
pr_up:
    ld e,a
    ld a,b
    cp SAYMAX                   ; as much as the window can show typed, with
    jr nc,pr_key                ; its allophones underneath and a row spare
    ld a,e
    ld (hl),a
    inc hl
    inc b
    push hl
    push bc
    call TXT_OUTPUT
    pop bc
    pop hl
    jr pr_key
pr_done:
    ld a,b
    ld (saylen),a
    call TXT_CUR_OFF
    jp syncpages                ; the typing only went to the page on show

;; The opening sentence, put through the same rules as anything typed.
;; Without them (the loader not used) it falls back to the allophones
;; written out by hand in headdata.inc.
speakintro:
    ld a,(hooked)
    or a
    jp z,speak
    ld hl,phonbuf
    ld (saytail),hl
    ld hl,intro1
    ld b,intro1len
    call CONVERT
    call breathe                ; a real pause after "head", and after
    ld hl,intro2                ; "C P C" - the sentence is hard to follow
    ld b,intro2len              ; without them
    call CONVERT
    call breathe
    ld hl,intro3
    ld b,intro3len
    call CONVERT
    ld hl,(saytail)
    ld (hl),#FF
    ld hl,phonbuf
    jp speakfrom

;; two PA5s: half a second of silence, whatever the speed setting
;; Three PA5s - 600 ms of silence on top of the full stop's own - because
;; the sentence runs on into the next one otherwise, and the "I" of "I LIVE"
;; is the first thing lost.
breathe:
    ld a,4
    call addphon
    ld a,4
    call addphon
    ld a,4
addphon:
    push hl
    push de
    ld hl,(saytail)
    ld de,sayend
    ex de,hl
    or a
    sbc hl,de
    jr z,ap_full
    ex de,hl
    ld (hl),a
    inc hl
    ld (saytail),hl
ap_full:
    pop de
    pop hl
    ret

abouttxt:
    defb 164," 2026 Michael Wessel (LambdaMikel)",13
    defb "& Claude",13,13
    defb "Head adapted from the University of Utah "
    defb "digitized face: F. I. Parke, ",34,"Computer "
    defb "Generated Animation of Faces",34," (1972), "
    defb "made alongside Ed Catmull's ",34,"A Computer "
    defb "Animated Hand",34,".",13,13
    defb "In 1985 Michael took a P.M. Computerheft, "
    defb "digitized the head by hand on graph paper, "
    defb "and wrote a Locomotive BASIC 1.0 program "
    defb "for his Schneider CPC 464 to draw it. It "
    defb "has been the LambdaMikel logo ever since.",13,13
    defb "40 years on, Claude Code animated it and "
    defb "gave it a voice, through the Amstrad SSA-1 "
    defb "or LambdaSpeak. Text-to-speech for the "
    defb "SP0256-AL2 adapted from the SSA-1 driver. "
    defb "Enjoy!",0

anykeytxt: defb 13,13,"Press any key.",0
nonrltxt:
    defb 13,13,"NRL.BIN was not loaded, so there is no "
    defb "prompt and only the sentence built in "
    defb "here can be spoken.",13,13
    defb "Start it with RUN",34,"VH - not HEAD.BIN.",13,13
    defb "SPACE says it again.  Q quits.",0
moretxt:   defb "...",0
hint1:     defb "  (, . change it)",0
hint2:     defb "ENTER speaks.  QUIT exits.",0

intro1:   defb "HELLO. I AM A VECTORIZED COMPUTER HED."
intro1end:
intro1len equ intro1end - intro1
intro2:   defb "I LIV IN THE C P C."
intro2end:
intro2len equ intro2end - intro2
intro3:   defb "JUST TYPE WHAT YOU WANT ME TO SAY."
intro3end:
intro3len equ intro3end - intro3

;; the text in saybuf/saylen -> allophones in phonbuf, #FF terminated

saywords:
    ld hl,phonbuf
    ld (saytail),hl
    ld a,(saylen)
    or a
    ret z
    ld b,a
    ld hl,saybuf
    call CONVERT                ; the 1985 rules, as a subroutine
    ld hl,(saytail)
    ld (hl),#FF                 ; and the end of what they said
    ret

saytail:  defw phonbuf
dbgpeek:  defs 16
asktxt:   defb "Say: ",0
fixedtxt: defb "HELLO THERE" 
saydesc:  defb 0
          defw 0
sayparm:  defw 0
saybuf:   defs SAYBUFLEN         ; as long a line as the window can show
fixbuf:   defs FIXBUFLEN         ; the same line with the exceptions in it
fxlen:    defb 0                 ; how long the word being looked up is
phonbuf:  defs 400              ; the allophones SAY produced - two per
                                ; typed character is the worst the rules do
sayend:
saylen:   defb 0
hooked:   defb 0
usedi:    defb 0
hookcnt:  defb 0
progress: defb 0
saycalls: defb 0
dbgfound: defb 0
dbgrom:   defb 0
dbgadr:   defw 0
dbginit:  defw 0
dbgdisc:  defb 0

;; ---------------------------------------------------------------
;; speech
;;
;; One allophone at a time: set the mouth, hand the byte to the chip, and
;; let the chip's own "ready" line decide when the next one goes - which
;; is also when the mouth moves again.  With no synthesiser fitted the
;; same loop runs off the data sheet's allophone durations, so the head
;; still mouths the sentence in silence.
;; ---------------------------------------------------------------
;; Bit 7 of the status is SBY, standby: 1 while the chip has nothing to
;; say.  An empty expansion port answers #80 as well, so idling is not
;; proof of anything - a PA5 is sent and the status has to go busy.  That
;; is the only reading a floating bus cannot produce.
spdetect:
    ld bc,SSA1
    in a,(c)
    and #C0                     ; bit 6 is LRQ, low when it wants a byte
    cp #80
    jr nz,spd_none
    ld a,4                      ; PA5, 200 ms of silence
    out (c),a
    ld d,0
spd_busy:
    in a,(c)
    and #80
    jr z,spd_yes                ; it went busy: something is listening
    dec d
    jr nz,spd_busy
spd_none:
    xor a
    ld (sppresent),a
    ret
spd_yes:
    ld a,1
    ld (sppresent),a
    ret

speak:
    ld hl,utter
speakfrom:
    push hl
    ld hl,blinkat
    ld (blinkatp),hl
    xor a
    ld (allocount),a
    ld (blinkphase),a
    pop hl
sp_next:
    ld a,(hl)
    inc a
    ret z                       ; #FF ends the sentence
    dec a
    cp 5                        ; a pause: play it as long as the speed
    jr nc,sp_notpause           ; setting says
    push hl
    ld e,a
    ld d,0
    ld hl,(pausemap)
    add hl,de
    ld a,(hl)
    pop hl
sp_notpause:
    push hl
    push af
    ld hl,allocount             ; time for a blink?
    inc (hl)
    ld a,(hl)
    ld hl,(blinkatp)
    cp (hl)
    jr nz,sp_noblink
    inc hl
    ld (blinkatp),hl
    ld a,1
    ld (blinkphase),a
sp_noblink:
    pop af
    ld e,a
    ld d,0
    ld hl,vismap
    add hl,de
    ld a,(hl)                   ; the viseme for this allophone
    push af                     ; ... kept for after the byte is sent
    ld a,(sppresent)
    or a
    jr z,sp_silent2
    ld bc,SSA1
sp_wait:
    in a,(c)
    and #40                     ; LRQ: clear means it can take another one
    jr z,sp_ready               ; now - waiting for the chip to go fully
    push bc                     ; idle instead left a gap after every
    push de                     ; allophone, which is most of what made
    call blinktick              ; it sound slow
    pop de
    pop bc
    jr sp_wait
sp_ready:
    out (c),e                   ; hand it over, and move the mouth while
    pop af                      ; it is being said rather than before
    push de
    call setmouth
    pop de
    jr sp_done
sp_silent2:
    pop af
    push de
    call setmouth
    pop de
    jr sp_silent
sp_silent:
    push de
    call blinktick
    pop de
    ld hl,durtab
    add hl,de
    ld e,(hl)
    ld d,0
    call delay                  ; the data sheet's duration instead
sp_done:
    pop hl
    inc hl
    jr sp_next

;; DE = 1/300 s to wait, paced against the firmware's clock rather than
;; counted out in a loop
delay:
    ld (delayn),de
    call KL_TIME_PLEASE
    ld (t0),hl
dly1:
    call KL_TIME_PLEASE
    ld de,(t0)
    or a
    sbc hl,de
    ld de,(delayn)
    or a
    sbc hl,de
    jr c,dly1
    ret

;; ---------------------------------------------------------------
;; mirrorhalf - columns 21..39 of every scanline, bit-reversed, into
;; columns 58..40.  The source pointer runs right and the destination
;; runs left, and they start (79-2*COLL) bytes apart on the same line.
;; Unrolled over the 19 columns: at 11 us a byte the loop overhead would
;; otherwise be a third of the work.
;; ---------------------------------------------------------------
COLL    equ HEADCOL             ; the columns the head reaches, from
COLW    equ HEADCOLW            ; the generator

mirrorhalf:
    ld b,0                      ; scanline
    ld de,COLL*8                ; scraddr wants a pixel, not a column
    call scraddr                ; HL = the first row's source; from there
    ld b,200                    ; it is stepped down a line at a time
mh_row:
    push bc
    push hl
    ld d,h
    ld e,l
    ld a,e
    add a,MIRRORC-2*COLL             ; the mirror of column COLL on this line
    ld e,a
    jr nc,mh_go
    inc d
mh_go:
    ld b,h
    ld c,l                      ; BC = source, so LD A,(BC) can read it
    ld h,revtab/256
    repeat COLW
    ld a,(bc)
    ld l,a
    ld a,(hl)
    ld (de),a
    inc bc
    dec de
    rend
    pop hl
    call scrdown
    pop bc
    dec b
    jp nz,mh_row                ; 19 unrolled columns put this out of
    ret                         ; DJNZ's reach



;; HL as decimal, no leading zeroes
putdec:
    xor a
    ld (pd_lead),a              ; per call: the second number printed would
    ld de,10000                 ; otherwise come out with the first one's
                                ; leading zeroes
    call pd_digit
    ld de,1000
    call pd_digit
    ld de,100
    call pd_digit
    ld de,10
    call pd_digit
    ld de,1
pd_digit:
    ld b,'0'-1
pd_1:
    inc b
    or a
    sbc hl,de
    jr nc,pd_1
    add hl,de
    ld a,b
    cp '0'
    jr nz,pd_out
    ld a,(pd_lead)
    or a
    ret z                       ; a leading zero, and nothing printed yet
    ld a,'0'
pd_out:
    push af
    ld a,1
    ld (pd_lead),a
    pop af
    jp TXT_OUTPUT
pd_lead: defb 0

timetxt: defb "Head drawn in ",0
mouthtxt: defb "Mouth moved in ",0
timetx2: defb " ticks of 1/300 s",0

sppresent: defb 0
lpcount: defb 9                  ; names left on this line of the listing
noclear: defb 0                  ; keep what is in the window for one turn
firstrun: defb 1
spsave:  defw 0
curvis:  defb REST               ; what the head should be showing...
cureye:  defb 0
pstate:  defb REST,0             ; ... and what each page actually shows
         defb REST,0
allocount: defb 0
blinkphase: defb 0
blinkatp: defw 0
drawbase: defb PAGE0            ; the page being drawn into...
viewbase: defb PAGE0            ; ... and the one on show
bcol:    defb 0
bw:      defb 0
brow:    defb 0
brows:   defb 0
bbuf:    defw 0
delayn:  defw 0
t0:      defw 0
t1:      defw 0
mouthmax: defw 0
ticks:   defw 0
curx:    defw 0
cury:    defb 0
tabptr:  defw 0

;; Clean copies of the two boxes, taken once the head is drawn.  They live
;; between the driver and the second screen page, out of reach of #9600.
mouthbuf equ #3800
eyebuf   equ mouthbuf + MOUTHCOLW*MOUTHROWS

tabend:
    assert tabend < #A600       ; AMSDOS keeps its workspace above that.
                                ; The old limit was #9600, the fixed
                                ; address the driver queued phonemes at -
                                ; but that queue is redirected now, so the
                                ; memory is ours again
    assert eyebuf + EYECOLW*EYEROWS < #4000

    save "HEAD.BIN", #8000, tabend-#8000, AMSDOS, start
