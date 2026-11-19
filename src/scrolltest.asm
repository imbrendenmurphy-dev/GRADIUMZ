; ---------------------------------------------------------------------------
;  GRADIUMZ - step 1b: optimised display engine / scroll test (Sharp MZ-700 PAL)
;
;  * 80x50 dot playfield built from the quarter-block characters F0-FF
;  * smooth 1-dot horizontal scrolling (two pre-shifted character maps)
;  * characters redrawn only on frames where the view moves,
;    colours only when it crosses a whole cell, and only on rows that need it
;  * the ship saves/restores the cells under it on the other frames
;  * top line shows spare time over the last 64 frames: WORST BEST (hex)
;    0000 in WORST means at least one frame overran
; ---------------------------------------------------------------------------
        DEVICE NOSLOT64K

VRAM    EQU 0D000h
CRAM    EQU 0D800h              ; = VRAM with bit 11 set (SET 3,H)
PPIA    EQU 0E000h              ; keyboard strobe (low nibble)
PPIB    EQU 0E001h              ; keyboard return, active low
PPIC    EQU 0E002h              ; bit 7 = /VBLK (0 during vertical blank)

ROWS    EQU 23                  ; playfield character rows (screen rows 1..23)
STRIDE  EQU 296                 ; must match tools/gen_level.py
BLOCK   EQU ROWS*STRIDE
SCRDIV  EQU 2                   ; scroll one dot every SCRDIV frames

        ORG 1200h
start:
        di
        ld sp,start

        ; clear screen: char 00, white on black
        ld hl,VRAM
        ld de,VRAM+1
        ld bc,999
        ld (hl),0
        ldir
        ld hl,CRAM
        ld de,CRAM+1
        ld bc,999
        ld (hl),70h
        ldir

        ; HUD
        ld hl,txt_1p
        ld de,VRAM+1
        ld c,70h
        call print
        ld hl,txt_hi
        ld de,VRAM+12
        call print
        ld hl,txt_mz
        ld de,VRAM+35
        ld c,20h                ; red
        call print
        ld hl,txt_bar
        ld de,VRAM+24*40
        ld c,51h                ; cyan on blue
        call print
        ld hl,CRAM+24*40+19     ; highlight one slot: blue on yellow
        ld b,4
.hilite:
        ld (hl),16h
        inc hl
        djnz .hilite

        ; full colour map once (rows that never change are set here only)
        ld hl,COL
        ld de,CRAM+40
        call blit

; ---------------------------------------------------------------------------
mainloop:
        call waitvbl
        call perf
        call restoreship        ; put back what the ship covered

        ld a,(dirty)
        or a
        jr z,.sprites           ; the view is still: nothing else to redraw

        ; ---- the view moved: redraw characters (ship cells included)
        xor a
        ld (dirty),a
        ld hl,(scrollx)
        srl h
        rr l                    ; L = cell offset, H = 0, carry = phase
        push af
        push hl
        ld de,CHR0
        jr nc,.ph0
        ld de,CHR1
.ph0:   add hl,de
        ld de,VRAM+40
        call blit
        pop hl
        pop af
        jr c,.sprites           ; odd phase: same cells as last step
        ld de,COL               ; crossed a cell boundary: colours too
        add hl,de
        ld de,CRAM+40
        call blitcol

.sprites:
        call drawship
        call showperf
        call input

        ld hl,frame
        inc (hl)
        ld a,(hl)
        cp SCRDIV
        jr c,mainloop
        ld (hl),0
        ld hl,(scrollx)
        inc hl
        ld a,h
        and 1
        ld h,a                  ; wrap at 512 dots
        ld (scrollx),hl
        ld a,1
        ld (dirty),a
        jp mainloop

; ---------------------------------------------------------------------------
; wait for the start of vertical blank; BC = loops spent waiting in display
waitvbl:
        ld bc,0
.inbl:  ld a,(PPIC)             ; if already in blank (overran), wait it out
        rlca
        jr nc,.inbl
.disp:  inc bc                  ; count while the picture is being drawn
        ld a,(PPIC)
        rlca
        jr c,.disp
        ret

; track worst/best spare time; publish every 64 frames.  in: BC
perf:
        ld hl,(pworst)
        or a
        sbc hl,bc
        jr c,.nw                ; worst < bc
        ld (pworst),bc
.nw:    ld hl,(pbest)
        or a
        sbc hl,bc
        jr nc,.nb               ; best >= bc
        ld (pbest),bc
.nb:    ld hl,pcount
        inc (hl)
        ld a,(hl)
        and 63
        ret nz
        ld hl,(pworst)
        ld (shworst),hl
        ld hl,(pbest)
        ld (shbest),hl
        ld hl,0FFFFh
        ld (pworst),hl
        ld hl,0
        ld (pbest),hl
        ret

; ---------------------------------------------------------------------------
; copy ROWS x 40 bytes, HL = source (row stride 296), DE = screen
blit:
        ld a,ROWS
.row:
        DUP 40
        ldi
        EDUP
        inc h                   ; +256 -> start of next source row
        dec a
        jp nz,.row
        ret

; as blit, but skips rows whose colours never change (rowflags = 0)
blitcol:
        ld ix,rowflags
        ld a,ROWS
.row:   bit 0,(ix+0)
        inc ix
        jr z,.skip
        DUP 40
        ldi
        EDUP
        inc h
        dec a
        jp nz,.row
        ret
.skip:  ld bc,STRIDE
        add hl,bc
        ex de,hl
        ld bc,40
        add hl,bc
        ex de,hl
        dec a
        jp nz,.row
        ret

; ---------------------------------------------------------------------------
; draw the ship at dot position (shipx, shipy), ORed into the background.
; The 4x2 cells underneath (chars and colours) are saved first.
drawship:
        ld a,(shipy)
        srl a
        inc a                   ; playfield starts on screen row 1
        call rowaddr
        ld a,(shipx)
        srl a
        ld e,a
        ld d,0
        add hl,de
        ld (savepos),hl
        ld a,(shipy)
        and 1
        add a,a
        ld b,a
        ld a,(shipx)
        and 1
        or b
        add a,a
        add a,a
        add a,a                 ; variant * 8
        ld e,a
        ld d,0
        ld ix,shipgfx
        add ix,de
        ld iy,savebuf
        ld c,2
.row:   ld b,4
.cell:  ld a,(hl)
        ld (iy+0),a             ; save char
        ld e,a
        set 3,h
        ld a,(hl)
        ld (iy+8),a             ; save colour
        ld d,a
        inc iy
        ld a,(ix+0)
        inc ix
        or a
        jr z,.skip
        ld a,d
        and 07h                 ; keep background colour
        or 70h                  ; white dots
        ld (hl),a
        res 3,h
        ld a,(ix-1)
        or e
        ld (hl),a
        set 3,h
.skip:  res 3,h
        inc hl
        djnz .cell
        ld de,36
        add hl,de
        dec c
        jr nz,.row
        ret

; put back the cells saved by drawship
restoreship:
        ld hl,(savepos)
        ld iy,savebuf
        ld de,36
        ld c,2
.row:   ld b,4
.cell:  ld a,(iy+0)
        ld (hl),a
        set 3,h
        ld a,(iy+8)
        ld (hl),a
        res 3,h
        inc iy
        inc hl
        djnz .cell
        add hl,de
        dec c
        jr nz,.row
        ret

; ---------------------------------------------------------------------------
input:
        ld a,0F7h               ; strobe 7: cursor keys
        ld (PPIA),a
        ld a,(PPIB)
        cpl
        ld b,a
        ld hl,shipy
        bit 5,b                 ; up
        jr z,.nu
        ld a,(hl)
        or a
        jr z,.nu
        dec (hl)
.nu:    bit 4,b                 ; down
        jr z,.nd
        ld a,(hl)
        cp 43
        jr nc,.nd
        inc (hl)
.nd:    ld hl,shipx
        bit 2,b                 ; left
        jr z,.nl
        ld a,(hl)
        or a
        jr z,.nl
        dec (hl)
.nl:    bit 3,b                 ; right
        ret z
        ld a,(hl)
        cp 72
        ret nc
        inc (hl)
        ret

; ---------------------------------------------------------------------------
showperf:
        ld de,VRAM+23
        ld hl,(shworst)
        call hex4
        inc de
        ld hl,(shbest)
hex4:   ld a,h
        call hex2
        ld a,l
hex2:   push af
        rrca
        rrca
        rrca
        rrca
        call hex1
        pop af
hex1:   and 0Fh
        cp 10
        jr c,.dig
        sub 9                   ; A..F -> display codes 01..06
        jr .put
.dig:   add a,20h               ; 0..9 -> display codes 20..29
.put:   ld (de),a
        inc de
        ret

; ---------------------------------------------------------------------------
; HL = VRAM + A*40
rowaddr:
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        ld de,VRAM
        add hl,de
        ret

; print 0-terminated ASCII string HL at screen DE with attribute C
print:
        ld a,(hl)
        or a
        ret z
        inc hl
        cp 'A'
        jr c,.nl
        sub 40h                 ; A..Z -> 01..1A
        jr .put
.nl:    cp '0'
        jr c,.sp
        sub 10h                 ; 0..9 -> 20..29
        jr .put
.sp:    xor a                   ; anything else -> blank
.put:   ld (de),a
        set 3,d
        ld a,c
        ld (de),a
        res 3,d
        inc de
        jr print

; ---------------------------------------------------------------------------
txt_1p:   DB "1P  00000",0
txt_hi:   DB "HI  50000",0
txt_mz:   DB "MZ700",0
txt_bar:  DB " SPEED MISSL SPRED BEAM  DRONE  SHLD   ",0

scrollx:  DW 0
dirty:    DB 1
frame:    DB 0
shipx:    DB 10
shipy:    DB 20
savepos:  DW VRAM+40
savebuf:  DS 16
pworst:   DW 0FFFFh
pbest:    DW 0
shworst:  DW 0
shbest:   DW 0
pcount:   DB 0

rowflags: INCBIN "../build/rowflags.bin"
shipgfx:  INCBIN "../build/ship.bin"
CHR0:     INCBIN "../build/level.bin"
CHR1      EQU CHR0+BLOCK
COL       EQU CHR0+2*BLOCK
progend:

        ASSERT progend < 0D000h
        SAVEBIN "build/scrolltest.bin", start, progend-start
