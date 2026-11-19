; ===========================================================================
;  GRADIUMZ - side-scrolling shooter for the Sharp MZ-700 (PAL)
;
;  Game loop runs at 25 fps (one tick = two video frames):
;    at vertical blank : copy the off-screen buffer to the screen (present)
;    rest of the tick  : input, game logic, then build the next picture in
;                        the off-screen buffer (scenery, then sprites)
;
;  Coordinates: x is in dots + 8 (so sprites can slide off the left edge),
;  y is in dots 0..45 inside the 23-row playfield (screen rows 1..23).
;
;  Controls: cursor keys move, SPACE fires, SHIFT or Z takes the power-up.
; ===========================================================================
        DEVICE NOSLOT64K

VRAM    EQU 0D000h
CRAM    EQU 0D800h              ; = VRAM with bit 11 set
PPIA    EQU 0E000h              ; keyboard strobe (low nibble)
PPIB    EQU 0E001h              ; keyboard return, active low
PPIC    EQU 0E002h              ; bit 7 = /VBLK (0 during vertical blank)

ROWS    EQU 23
STRIDE  EQU 296                 ; level map row stride (tools/gen_level.py)
BLOCK   EQU ROWS*STRIDE

SNDC    EQU 0E004h              ; 8253 counter 0 (sound)
SNDM    EQU 0E007h              ; 8253 mode register
SNDG    EQU 0E008h              ; bit 0 = sound gate

NOBJ    EQU 14                  ; enemies, capsules, explosions, bullets
OSIZE   EQU 8
NSHOTS  EQU 8                   ; player + drone shots
SSIZE   EQU 4                   ; x (0 = free), y, dy, kind (1 = beam)

; object fields
O_TYPE  EQU 0
O_X     EQU 1
O_Y     EQU 2
O_T     EQU 3                   ; timer
O_A     EQU 4                   ; dart: base y   bullet: dx
O_B     EQU 5                   ; dart: phase    bullet: dy   spinner: anim
O_F     EQU 6                   ; flags: bit0 dart-wave member, bit1 carrier,
                                ;        bit2 ceiling turret

T_DART  EQU 1                   ; enemies first (type = points in hundreds)
T_SPIN  EQU 2
T_TURR  EQU 3
T_CAPS  EQU 4
T_EXPL  EQU 5
T_EBUL  EQU 6

DSIZE   EQU 5                   ; scenery column: ceiling, floor y, style,
                                ;                 star y, dot x

        INCLUDE "../build/sprites.inc"

        ORG 1200h
start:
        di
        ld sp,start
        ld hl,CBUF              ; clear buffers and variables
        ld de,CBUF+1
        ld bc,bss_end-CBUF-1
        ld (hl),0
        ldir
        call sndinit
        ; fall through to the title

; ===========================================================================
;  title screen / attract mode
; ===========================================================================
title:
        ld sp,start
        call sndstop
        xor a
        ld (demo),a
        call initscreen
        ld hl,TITLE
        ld de,VRAM+40
        ld bc,920
        ldir
        ld hl,TITLE+920
        ld de,CRAM+40
        ld bc,920
        ldir
        ld hl,400               ; 16 seconds, then the demo
        ld (ttimer),hl
        ld a,10h
        ld (tkey),a             ; space must be released first
.loop:  call waittick
        call hud
        ld hl,tick
        inc (hl)
        ; flash PUSH SPACE KEY
        ld a,(tick)
        and 16
        ld a,60h
        jr z,.fl
        xor a
.fl:    ld hl,CRAM+12*40
        ld b,40
.f1:    ld (hl),a
        inc hl
        djnz .f1
        ; roll the logo colours every 4 ticks
        ld a,(tick)
        and 3
        jr nz,.key
        ld a,(cycpos)
        inc a
        and 7
        ld (cycpos),a
        ld de,CRAM+4*40
        ld c,5
.cr:    ld hl,logocyc
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        ld b,40
.cc:    ld (de),a
        inc de
        djnz .cc
        ld a,(cycpos)
        add a,6
        sub c                   ; next row uses the next palette entry
        and 7
        dec c
        jr nz,.cr
.key:   call trainmenu
        ld a,0F6h               ; space pressed (newly)?
        ld (PPIA),a
        ld a,(PPIB)
        cpl
        and 10h
        ld b,a
        ld a,(tkey)
        cpl
        and b
        ld c,a
        ld a,b
        ld (tkey),a
        ld a,c
        or a
        ld a,0
        jr nz,startgame
        ld hl,(ttimer)
        dec hl
        ld (ttimer),hl
        ld a,h
        or l
        jr nz,.loop
        inc a                   ; A = 1: demo

; A = 0 for a real game, 1 for the demo
startgame:
        ld sp,start
        ld (demo),a
        or a
        jr nz,.d
        ld a,(tsel)             ; a real game uses the trainer settings
        ld (stage0),a
        ld a,(tinf)
        ld (inf),a
        ld a,(tinv)
        ld (inv),a
        jr .g
.d:     xor a                   ; the demo never does
        ld (stage0),a
        ld (inf),a
        ld (inv),a
.g:     call initscreen
        call newgame
        ld hl,750               ; demo lasts 30 seconds at most
        ld (dtimer),hl

; ---------------------------------------------------------------------------
mainloop:
        call waittick
        call perf
        call present
        call hud
        call vpoll
        call readinput
        call updplayer
        call updshots
        call updmissile
        call vpoll
        call updobjs
        call updboss
        call spawner
        call collide
        call vpoll
        call scroll
        call updstars
        call genmap
        call buildbg
        call drawstars
        call drawall
        call markdirty
        ld hl,tick
        inc (hl)
        jp mainloop

; ---------------------------------------------------------------------------
; title-screen trainer: 1-4 start stage, T infinite lives, I invincible
trainmenu:
        ld c,0
        ld a,0F2h               ; T: strobe 2 bit 4
        ld (PPIA),a
        ld a,(PPIB)
        bit 4,a
        jr nz,.a
        set 0,c
.a:     ld a,0F3h               ; I: strobe 3 bit 7
        ld (PPIA),a
        ld a,(PPIB)
        bit 7,a
        jr nz,.b
        set 1,c
.b:     ld a,0F5h               ; 1-4: strobe 5 bits 7..4
        ld (PPIA),a
        ld a,(PPIB)
        cpl
        ld b,a
        bit 7,b
        jr z,.d1
        set 2,c
.d1:    bit 6,b
        jr z,.d2
        set 3,c
.d2:    bit 5,b
        jr z,.d3
        set 4,c
.d3:    bit 4,b
        jr z,.d4
        set 5,c
.d4:    bit 3,b                 ; 5
        jr z,.d5
        set 6,c
.d5:    ld a,(tkeys)            ; newly pressed keys
        cpl
        and c
        ld b,a
        ld a,c
        ld (tkeys),a
        ld a,b
        or a
        jr z,.draw
        ld hl,400               ; someone is busy: hold off the demo
        ld (ttimer),hl
        bit 0,b
        jr z,.n0
        ld a,(tinf)
        xor 1
        ld (tinf),a
.n0:    bit 1,b
        jr z,.n1
        ld a,(tinv)
        xor 1
        ld (tinv),a
.n1:    bit 2,b
        jr z,.s1
        xor a
        ld (tsel),a
.s1:    bit 3,b
        jr z,.s2
        ld a,1
        ld (tsel),a
.s2:    bit 4,b
        jr z,.s3
        ld a,2
        ld (tsel),a
.s3:    bit 5,b
        jr z,.s4
        ld a,3
        ld (tsel),a
.s4:    bit 6,b
        jr z,.draw
        ld a,4
        ld (tsel),a
.draw:  ld hl,txt_tm            ; build the status line and print it
        ld de,tmbuf
        ld bc,41
        ldir
        ld a,(tsel)
        add a,'1'
        ld (tmbuf+6),a
        ld a,(tinf)
        or a
        jr z,.l3
        ld hl,txt_inf
        ld de,tmbuf+18
        ld bc,3
        ldir
.l3:    ld a,(tinv)
        or a
        jr z,.v0
        ld hl,txt_yes
        ld de,tmbuf+37
        ld bc,3
        ldir
.v0:    ld hl,tmbuf
        ld de,VRAM+17*40
        ld c,50h
        jp print

; ===========================================================================
;  timing
; ===========================================================================
; count falling edges of /VBLK (start of vertical blank).  Called often
; enough during the tick that the long blanking period is never missed.
; Also drives the sound.
vpoll:
        call sndfast
        push af
        push hl
        ld a,(PPIC)
        and 80h
        ld hl,vprev
        cp (hl)
        jr z,.x
        ld (hl),a
        or a
        jr nz,.x
        ld hl,vcount
        inc (hl)
.x:     pop hl
        pop af
        ret

; wait until two frames have started since the last tick (or one more
; if we already overran).  BC = idle loops.
waittick:
        ld bc,0
        ld a,(vcount)
        inc a
        cp 3
        jr nc,.t
        ld a,2
.t:     ld e,a
.loop:  inc bc
        call vpoll
        ld a,(vcount)
        cp e
        jr c,.loop
        xor a
        ld (vcount),a
        ret

; worst idle count over the last 64 ticks, for the HUD.  in: BC
perf:
        ld hl,(pworst)
        or a
        sbc hl,bc
        jr c,.nw
        ld (pworst),bc
.nw:    ld hl,pcount
        inc (hl)
        ld a,(hl)
        and 63
        ret nz
        ld hl,(pworst)
        ld (shworst),hl
        ld hl,0FFFFh
        ld (pworst),hl
        ret

; ===========================================================================
;  screen
; ===========================================================================
initscreen:
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
        ld hl,txt_1p
        ld de,VRAM+1
        ld c,70h
        call print
        ld hl,txt_hi
        ld de,VRAM+12
        call print
        ld hl,txt_mz
        ld de,VRAM+35
        ld c,20h
        call print
        ld hl,txt_bar
        ld de,VRAM+24*40
        ld c,51h
        call print
        ld a,0FFh               ; little ship icon for lives
        ld (VRAM+23),a
        ld a,0FCh
        ld (VRAM+24),a
        ld a,50h
        ld (CRAM+23),a
        ld (CRAM+24),a
        ret

; copy the off-screen buffer to the screen: all characters, colours only
; for rows marked dirty
present:
        ld hl,CBUF
        ld de,VRAM+40
        ld a,ROWS
.r:
        DUP 40
        ldi
        EDUP
        dec a
        jp nz,.r
        call sndfast
        ld hl,ABUF
        ld de,CRAM+40
        ld ix,dirty
        ld a,ROWS
.c:     bit 0,(ix+0)
        inc ix
        jr z,.s
        DUP 40
        ldi
        EDUP
        dec a
        jp nz,.c
        ret
.s:     ld bc,40
        add hl,bc
        ex de,hl
        add hl,bc
        ex de,hl
        dec a
        jp nz,.c
        ret

; copy ROWS x 40 bytes, HL = map source (row stride 296), DE = buffer
blit:
        ld a,ROWS
.row:
        DUP 40
        ldi
        EDUP
        inc h
        call vpoll              ; keeps the sound moving
        dec a
        jp nz,.row
        ret

; scenery into the off-screen buffer
buildbg:
        ld hl,(scrollx)
        srl h
        rr l                    ; L = cell offset, carry = odd dot
        ld de,CHR0
        jr nc,.p0
        ld de,CHR1
.p0:    ld a,(lastcell)
        cp l
        ld a,0
        jr z,.same
        inc a
.same:  ld (cellchg),a
        ld a,l
        ld (lastcell),a
        push hl
        add hl,de
        ld de,CBUF
        call blit
        call vpoll
        pop hl
        ld de,COL
        add hl,de
        ld de,ABUF
        call blit
        jp vpoll

; dirty[r] = sprites there now or last tick, or scenery colours moved
markdirty:
        ld a,(cellchg)
        ld c,a
        ld hl,touch
        ld de,ptouch
        ld ix,(rfptr)
        ld iy,dirty
        ld b,ROWS
.l:     ld a,(ix+0)
        and c
        or (hl)
        ex de,hl
        or (hl)
        ex de,hl
        ld (iy+0),a
        ld a,(hl)
        ld (de),a
        ld (hl),0
        inc hl
        inc de
        inc ix
        inc iy
        djnz .l
        ld a,(forceall)
        or a
        ret z
        xor a
        ld (forceall),a
        ld hl,dirty
        ld b,ROWS
.f:     ld (hl),1
        inc hl
        djnz .f
        ret

scroll:
        ld a,(scrolling)        ; stopped for the boss
        or a
        ret z
        ld hl,(scabs)
        inc hl
        ld (scabs),hl
        ld hl,(scrollx)
        inc hl
        ld a,h
        and 1
        ld h,a
        ld (scrollx),hl
        ret

; ---------------------------------------------------------------------------
; draw sprite into the buffer.  B = x, C = y, HL = graphic, E = colour (fg<<4)
; Preserves IX, IY.
drawspr:
        ld a,e
        ld (.fgop+1),a
        ld a,c
        and 1
        add a,a
        ld d,a
        ld a,b
        and 1
        or d
        add a,a
        add a,a
        add a,a
        ld e,a
        ld d,0
        add hl,de
        ld (ds_gfx),hl
        ld a,b
        srl a
        sub 4
        ld (ds_col),a
        ld a,c
        srl a
        ld (ds_row),a
        ld a,2
        ld (ds_n),a
.row:   ld a,(ds_row)
        cp ROWS
        ret nc
        ld e,a
        ld d,0
        ld hl,touch
        add hl,de
        ld (hl),1
        ld hl,row40
        add hl,de
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld de,CBUF
        add hl,de               ; HL = buffer row
        ld a,(ds_col)
        ld c,a
        ld de,(ds_gfx)
        ld b,4
.cell:  ld a,(de)
        inc de
        or a
        jr z,.next
        ex af,af'
        ld a,c
        cp 40                   ; also rejects negative columns
        jr nc,.next
        push hl
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ex af,af'
        or (hl)
        ld (hl),a
        ld a,h
        add a,4                 ; ABUF = CBUF + 400h
        ld h,a
        ld a,(hl)
        and 07h
.fgop:  or 70h                  ; patched with the colour
        ld (hl),a
        pop hl
.next:  inc c
        djnz .cell
        ld (ds_gfx),de
        ld hl,ds_row
        inc (hl)
        ld hl,ds_n
        dec (hl)
        jr nz,.row
        ret

; ===========================================================================
;  HUD
; ===========================================================================
hud:
        ld hl,score
        ld de,VRAM+4
        call bcd6
        ld hl,hiscore
        ld de,VRAM+15
        call bcd6
        ld a,(lives)
        add a,20h
        ld (VRAM+25),a
        ld a,(bstate)           ; boss on screen: health bar instead
        or a
        jr z,.perf
        cp 4
        jr c,bossbar
.perf:  ld hl,VRAM+27           ; clear the bar area
        ld b,8
.c:     ld (hl),0
        set 3,h
        ld (hl),70h
        res 3,h
        inc hl
        djnz .c
        ld hl,(shworst)
        ld de,VRAM+28
        jp hex4

; 8-cell bar in columns 27..34, half a cell per sixteenth of health
bossbar:
        ld a,(bfrac)
        ld c,40h                ; green
        cp 9
        jr nc,.col
        ld c,60h                ; yellow
        cp 5
        jr nc,.col
        ld c,20h                ; red
.col:   ld hl,VRAM+27
        ld b,8
.l:     ld e,0FFh               ; full cell
        cp 2
        jr nc,.put
        ld e,0F5h               ; left half
        cp 1
        jr z,.put
        ld e,0F0h               ; empty
.put:   ld (hl),e
        set 3,h
        ld (hl),c
        res 3,h
        inc hl
        sub 2
        jr nc,.n
        xor a
.n:     djnz .l
        ret

bcd6:   ld b,3
.l:     ld a,(hl)
        rrca
        rrca
        rrca
        rrca
        and 0Fh
        add a,20h
        ld (de),a
        inc de
        ld a,(hl)
        and 0Fh
        add a,20h
        ld (de),a
        inc de
        inc hl
        djnz .l
        ret

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
        sub 9
        jr .put
.dig:   add a,20h
.put:   ld (de),a
        inc de
        ret

; power-up bar: highlight the slot at barpos
drawbar:
        ld hl,CRAM+24*40
        ld b,40
.c:     ld (hl),51h
        inc hl
        djnz .c
        ld a,(barpos)
        cp 6
        ret nc
        add a,a
        ld e,a
        ld d,0
        ld hl,slots
        add hl,de
        ld e,(hl)
        inc hl
        ld b,(hl)
        ld hl,CRAM+24*40
        add hl,de
.h:     ld (hl),16h
        inc hl
        djnz .h
        ret

; add A (BCD hundreds) to the score, update the high score
addscore:
        push bc
        ld hl,score+1
        add a,(hl)
        daa
        ld (hl),a
        dec hl
        ld a,(hl)
        adc a,0
        daa
        ld (hl),a
        ld a,(demo)             ; the demo never sets a high score
        or a
        jr nz,.x
        ld hl,score
        ld de,hiscore
        ld b,3
.c:     ld a,(de)
        cp (hl)
        jr c,.new
        jr nz,.x
        inc hl
        inc de
        djnz .c
        jr .x
.new:   ld hl,score
        ld de,hiscore
        ld bc,3
        ldir
.x:     pop bc
        ret

; ===========================================================================
;  game state
; ===========================================================================
newgame:
        ld hl,objs
        ld b,NOBJ*OSIZE
.c:     ld (hl),0
        inc hl
        djnz .c
        xor a
        ld (score),a
        ld (score+1),a
        ld (score+2),a
        ld (gstate),a
        ld (loopn),a
        ld a,(stage0)
        ld (stage),a
        ld a,3
        ld (lives),a
        call respawn
        jp startlevel

respawn:
        ld a,16
        ld (px),a
        ld a,20
        ld (py),a
        xor a
        ld (pstate),a
        ld (spread),a
        ld (beam),a
        ld (hasmiss),a
        ld (drones),a
        ld (shield),a
        ld (mx),a
        ld (cool),a
        ld (thead),a
        ld a,60
        ld (invuln),a
        ld a,2
        ld (pspeed),a
        ld a,0FFh
        ld (barpos),a
        ld hl,shots
        ld b,NSHOTS*SSIZE
.s:     ld (hl),0
        inc hl
        djnz .s
        ld hl,trailx            ; drones start on top of the ship
        ld b,32
.tx:    ld (hl),16
        inc hl
        djnz .tx
        ld hl,traily
        ld b,32
.ty:    ld (hl),20
        inc hl
        djnz .ty
        jp drawbar

; ---------------------------------------------------------------------------
readinput:
        ld a,(demo)
        or a
        jp nz,aiinput
        ld a,0F7h               ; strobe 7: cursor keys (bits 2..5)
        ld (PPIA),a
        ld a,(PPIB)
        cpl
        and 3Ch
        ld c,a
        ld a,0F6h               ; strobe 6 bit 4: space = fire
        ld (PPIA),a
        ld a,(PPIB)
        bit 4,a
        jr nz,.nf
        set 0,c
.nf:    ld a,0F8h               ; strobe 8 bit 0: shift = power-up
        ld (PPIA),a
        ld a,(PPIB)
        bit 0,a
        jr nz,.ns
        set 1,c
.ns:    ld a,0F1h               ; strobe 1 bit 6: Z = power-up
        ld (PPIA),a
        ld a,(PPIB)
        bit 6,a
        jr nz,.nz
        set 1,c
.nz:    ld a,(joy)
        cpl
        and c
        ld (joynew),a
        ld a,c
        ld (joy),a
        ret

; ---------------------------------------------------------------------------
; demo autopilot: chase the nearest enemy or capsule ahead, steer clear of
; the cavern walls, keep firing and take useful power-ups
aiinput:
        ld a,0F6h               ; a real SPACE press starts a game
        ld (PPIA),a
        ld a,(PPIB)
        bit 4,a
        jr nz,.ai
        xor a
        jp startgame
.ai:    ld a,1                  ; always firing
        ld (aijoy),a
        ld ix,objs
        ld b,NOBJ
        ld d,0FFh               ; nearest x so far
        ld e,20                 ; target y (default: mid screen)
.f:     ld a,(ix+O_TYPE)        ; enemies and capsules
        dec a
        cp T_CAPS
        jr nc,.nx
        ld a,(px)
        ld h,a
        ld a,(ix+O_X)
        cp h
        jr c,.nx                ; behind us
        cp d
        jr nc,.nx
        ld d,a
        ld e,(ix+O_Y)
.nx:    push de
        ld de,OSIZE
        add ix,de
        pop de
        djnz .f
        ld hl,aijoy
        ld a,(py)
        cp e
        jr z,.h
        jr c,.dn
        set 5,(hl)              ; up
        jr .h
.dn:    set 4,(hl)              ; down
.h:     ld a,(px)               ; hover around x = 26..34
        cp 26
        jr nc,.h1
        set 3,(hl)
        jr .safe
.h1:    cp 34
        jr c,.safe
        set 2,(hl)
.safe:  ld a,(px)               ; wall straight ahead?
        add a,9
        ld b,a
        ld a,(py)
        inc a
        ld c,a
        call solidat
        jr z,.up
        ld hl,aijoy
        res 3,(hl)
        set 2,(hl)
        res 4,(hl)
        res 5,(hl)
        ld a,(py)
        cp 22
        jr c,.goup
        set 5,(hl)              ; low down: climb
        jr .up
.goup:  set 4,(hl)              ; high up: dive
.up:    ld hl,aijoy             ; moving up into the ceiling?
        bit 5,(hl)
        jr z,.down
        ld a,(px)
        add a,4
        ld b,a
        ld a,(py)
        sub 3
        ld c,a
        call solidat
        jr z,.down
        ld hl,aijoy
        res 5,(hl)
.down:  ld hl,aijoy             ; moving down into the floor?
        bit 4,(hl)
        jr z,.pow
        ld a,(px)
        add a,4
        ld b,a
        ld a,(py)
        add a,5
        ld c,a
        call solidat
        jr z,.pow
        ld hl,aijoy
        res 4,(hl)
.pow:   ld a,(barpos)           ; take SPEED (to 3), MISSL, BEAM, DRONE
        or a
        jr nz,.p1
        ld a,(pspeed)
        cp 3
        jr c,.take
        jr .done
.p1:    cp 1
        jr nz,.p3
        ld a,(hasmiss)
        or a
        jr z,.take
        jr .done
.p3:    cp 3
        jr nz,.p4
        ld a,(beam)
        or a
        jr z,.take
        jr .done
.p4:    cp 4
        jr nz,.done
        ld a,(drones)
        cp 2
        jr nc,.done
.take:  ld hl,aijoy
        set 1,(hl)
.done:  ld a,(aijoy)
        ld c,a
        jp readinput.nz

; ---------------------------------------------------------------------------
updplayer:
        ld a,(demo)
        or a
        jr z,.real
        ld hl,(dtimer)          ; demo: back to the title after 30 seconds
        dec hl
        ld (dtimer),hl
        ld a,h
        or l
        jp z,title
        ld a,(pstate)           ; ... or once the first ship is lost
        or a
        jr z,.real
        ld a,(ptimer)
        cp 1
        jp z,title
.real:  ld a,(gstate)
        or a
        jr z,.play
        ld hl,gtimer
        dec (hl)
        ret nz
        jp title
.play:  ld a,(pstate)
        or a
        jr z,.alive
        ld hl,ptimer
        dec (hl)
        ret nz
        ld a,(lives)
        or a
        jp nz,respawn
        ld a,1
        ld (gstate),a
        ld a,125
        ld (gtimer),a
        ret
.alive: ld a,(invuln)
        or a
        jr z,.ni
        dec a
        ld (invuln),a
.ni:    ld a,(pspeed)
        ld d,a
        ld a,(joy)
        ld e,a
        bit 5,e                 ; up
        jr z,.nu
        ld a,(py)
        sub d
        jr nc,.u1
        xor a
.u1:    ld (py),a
.nu:    bit 4,e                 ; down
        jr z,.nd
        ld a,(py)
        add a,d
        cp 43
        jr c,.d1
        ld a,43
.d1:    ld (py),a
.nd:    bit 2,e                 ; left
        jr z,.nl
        ld a,(px)
        sub d
        cp 8
        jr nc,.l1
        ld a,8
.l1:    ld (px),a
.nl:    bit 3,e                 ; right
        jr z,.nr
        ld a,(px)
        add a,d
        cp 80
        jr c,.r1
        ld a,80
.r1:    ld (px),a
.nr:    ld a,(thead)            ; record the path for the drones
        ld e,a
        ld d,0
        ld hl,trailx
        add hl,de
        ld a,(px)
        cp (hl)
        jr nz,.rec
        ld hl,traily
        add hl,de
        ld a,(py)
        cp (hl)
        jr z,.norec
.rec:   ld a,e
        inc a
        and 31
        ld (thead),a
        ld e,a
        ld hl,trailx
        add hl,de
        ld a,(px)
        ld (hl),a
        ld hl,traily
        add hl,de
        ld a,(py)
        ld (hl),a
.norec: ld a,(joy)
        ld e,a
        ld hl,cool
        ld a,(hl)
        or a
        jr z,.c0
        dec (hl)
        jr .pw
.c0:    bit 0,e
        jr z,.pw
        ld (hl),3
        call fire
.pw:    ld a,(joynew)
        bit 1,a
        ret z
        ; take the highlighted power-up (if it is not already maxed out)
        ld a,(barpos)
        cp 6
        ret nc
        add a,a
        ld e,a
        ld d,0
        ld hl,powtab
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

powtab: DW p_speed,p_miss,p_spread,p_beam,p_drone,p_shield

p_speed:
        ld a,(pspeed)
        cp 4
        ret nc
        inc a
        ld (pspeed),a
        jr pused
p_miss: ld a,(hasmiss)
        or a
        ret nz
        inc a
        ld (hasmiss),a
        jr pused
p_spread:
        ld a,(spread)
        or a
        ret nz
        inc a
        ld (spread),a
        xor a
        ld (beam),a             ; SPRED and BEAM replace each other
        jr pused
p_beam: ld a,(beam)
        or a
        ret nz
        inc a
        ld (beam),a
        xor a
        ld (spread),a
        jr pused
p_drone:
        ld a,(drones)
        cp 2
        ret nc
        inc a
        ld (drones),a
        jr pused
p_shield:
        ld a,(shield)
        cp 5
        ret nc
        ld a,5
        ld (shield),a
pused:  ld a,0FFh
        ld (barpos),a
        ld hl,SFX_POWER
        call sfx
        jp drawbar

; enemy or bullet touched the player: the shield takes it if there is one
phit:   ld a,(shield)
        or a
        jp z,pdie
        dec a
        ld (shield),a
        ld hl,SFX_CLANK
        jp sfx

pdie:
        ld a,(inv)              ; trainer: invincible
        or a
        ret nz
        ld a,(invuln)
        or a
        ret nz
        ld a,(pstate)
        or a
        ret nz
        inc a
        ld (pstate),a
        ld a,50
        ld (ptimer),a
        ld a,(inf)              ; trainer: infinite lives
        or a
        jr nz,.keep
        ld hl,lives
        dec (hl)
.keep:
        ld hl,SFX_DEATH
        call sfx
        call newobj
        ret c
        ld (iy+O_TYPE),T_EXPL
        ld a,(px)
        ld (iy+O_X),a
        ld a,(py)
        ld (iy+O_Y),a
        ret

; ---------------------------------------------------------------------------
; shots: SSIZE bytes each = x (0 = free), y, dy (0 or -1), kind (1 = beam)
; Each shooter (ship, drones) may have 2 straight and 1 diagonal shot out.
fire:
        ld hl,SFX_SHOT
        call sfx
        ld a,(px)
        add a,6
        ld b,a
        ld a,(py)
        inc a
        ld c,a
        call fireone
        ld a,(drones)
        or a
        jr z,.m
        ld a,1
        call dronepos
        call .dfire
        ld a,(drones)
        cp 2
        jr c,.m
        ld a,2
        call dronepos
        call .dfire
.m:     ld a,(hasmiss)
        or a
        ret z
        ld a,(mx)
        or a
        ret nz
        ld a,(px)
        add a,3
        ld (mx),a
        ld a,(py)
        add a,2
        ld (my),a
        ret
.dfire: ld a,b
        add a,5
        ld b,a
        inc c
        jp fireone

; B = x, C = y: launch a straight (or beam) shot and, with SPRED, a diagonal
fireone:
        ld e,0
        call countshots
        ld l,a
        ld a,(drones)
        inc a
        add a,a                 ; limit = 2 per shooter
        sub l
        jr z,.d
        jr c,.d
        push bc
        call newshot
        pop bc
        jr c,.d
        ld (hl),b
        inc hl
        ld (hl),c
        inc hl
        ld (hl),0
        inc hl
        ld a,(beam)
        ld (hl),a
.d:     ld a,(spread)
        or a
        ret z
        ld e,0FFh
        call countshots
        ld l,a
        ld a,(drones)
        inc a                   ; limit = 1 per shooter
        sub l
        ret z
        ret c
        push bc
        call newshot
        pop bc
        ret c
        ld a,b
        sub 2
        ld (hl),a
        inc hl
        ld (hl),c
        inc hl
        ld (hl),0FFh
        inc hl
        ld (hl),0
        ret

; A = number of live shots whose dy equals E.  Preserves BC.
countshots:
        push bc
        ld hl,shots
        ld b,NSHOTS
        ld c,0
.l:     ld a,(hl)
        or a
        jr z,.n
        inc hl
        inc hl
        ld a,(hl)
        dec hl
        dec hl
        cp e
        jr nz,.n
        inc c
.n:     inc hl
        inc hl
        inc hl
        inc hl
        djnz .l
        ld a,c
        pop bc
        ret

newshot:
        ld hl,shots
        ld b,NSHOTS
        ld de,SSIZE
.l:     ld a,(hl)
        or a
        ret z                   ; carry clear = found
        add hl,de
        djnz .l
        scf
        ret

; A = drone number (1, 2) -> B = x, C = y of that drone's trail point
dronepos:
        add a,a
        add a,a
        add a,a                 ; 8 trail steps behind per drone
        ld b,a
        ld a,(thead)
        sub b
        and 31
        ld e,a
        ld d,0
        ld hl,trailx
        add hl,de
        ld b,(hl)
        ld hl,traily
        add hl,de
        ld c,(hl)
        ret

updshots:
        ld iy,shots
        ld b,NSHOTS
.l:     ld a,(iy+0)
        or a
        jr z,.n
        ld c,4                  ; speed: straight 4, diagonal 3, beam 6
        ld a,(iy+2)
        or a
        jr z,.st
        ld c,3
.st:    ld a,(iy+3)
        or a
        jr z,.sp
        ld c,6
.sp:    ld a,(iy+0)
        add a,c
        cp 88
        jr nc,.kill
        ld (iy+0),a
        ld a,(iy+1)
        add a,(iy+2)
        cp 46
        jr nc,.kill
        ld (iy+1),a
        push bc
        ld a,(iy+3)             ; check the scenery at the shot's front end
        or a
        ld a,2
        jr z,.k
        ld a,6
.k:     add a,(iy+0)
        ld b,a
        ld c,(iy+1)
        call solidat
        pop bc
        jr z,.n
.kill:  ld (iy+0),0
.n:     ld de,SSIZE
        add iy,de
        djnz .l
        ret

; missile: drops from the ship, then runs along the ground
updmissile:
        ld a,(mx)
        or a
        ret z
        add a,2
        cp 88
        jr nc,.kill
        ld (mx),a
        ld b,a
        inc b
        ld a,(my)
        add a,2
        ld c,a
        call solidat            ; anything under it?
        jr nz,.ground
        ld a,(my)               ; no: fall (up to two dots)
        inc a
        cp 44
        jr nc,.kill
        ld (my),a
        inc c
        call solidat
        ret nz
        ld a,(my)
        inc a
        cp 44
        jr nc,.kill
        ld (my),a
        ret
.ground:
        inc b                   ; ground ahead rising? climb
        ld a,(my)
        inc a
        ld c,a
        call solidat
        ret z
        ld a,(my)
        or a
        jr z,.kill
        dec a
        ld (my),a
        dec c
        call solidat            ; still blocked: hit a wall
        ret z
.kill:  xor a
        ld (mx),a
        ret

; ---------------------------------------------------------------------------
; is there a terrain dot at x = B, y = C?  NZ = solid.  Preserves BC, IX, IY.
solidat:
        ld a,c
        cp 46
        jr nc,.no
        ld a,b
        sub 8
        jr c,.no
        cp 80
        jr nc,.no
        push bc
        ld e,a
        ld d,0
        ld a,c
        and 1
        add a,a
        ld b,a                  ; B = 2 * bottom-half
        ld hl,(scrollx)
        add hl,de               ; map dot column
        srl h
        rr l                    ; HL = map cell, carry = right half
        jr nc,.lh
        inc b                   ; B = bit number in the character
.lh:    ex de,hl                ; DE = cell
        ld a,c
        and 0FEh                ; row * 2
        ld l,a
        ld h,0
        push de
        ld de,row296
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        pop de
        add hl,de               ; HL = row*296 + cell
        push hl
        ld de,COL
        add hl,de
        ld a,(hl)
        pop hl
        cp 70h                  ; anything but sky colour is scenery
        jr z,.no2
        ld de,CHR0
        add hl,de
        ld a,(hl)
        inc b
.sh:    rrca
        djnz .sh
        pop bc
        sbc a,a                 ; FF if the dot is set
        ret
.no2:   pop bc
.no:    xor a
        ret

; ===========================================================================
;  objects
; ===========================================================================
newobj:                         ; IY = free slot, carry set if none
        ld iy,objs
        ld b,NOBJ
        ld de,OSIZE
.l:     ld a,(iy+O_TYPE)
        or a
        jr z,.f
        add iy,de
        djnz .l
        scf
        ret
.f:     ld (iy+O_T),a
        ld (iy+O_A),a
        ld (iy+O_B),a
        ld (iy+O_F),a
        ret

updobjs:
        ld ix,objs
        ld b,NOBJ
.l:     push bc
        ld a,(ix+O_TYPE)
        or a
        call nz,.disp
        pop bc
        ld de,OSIZE
        add ix,de
        call vpoll
        djnz .l
        ret
.disp:  add a,a
        ld e,a
        ld d,0
        ld hl,updtab-2
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

updtab: DW u_dart,u_spin,u_turr,u_caps,u_expl,u_ebul

objfree:
        ld (ix+O_TYPE),0
        ret

u_dart: ld a,(ix+O_X)
        sub 2
        cp 2
        jr c,objfree
        ld (ix+O_X),a
        ld a,(ix+O_B)
        inc a
        and 31
        ld (ix+O_B),a
        ld hl,sine
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        add a,(ix+O_A)
        ld (ix+O_Y),a
        ret

u_spin: ld a,(ix+O_X)
        dec a
        cp 2
        jr c,objfree
        ld (ix+O_X),a
        inc (ix+O_B)
        bit 0,(ix+O_B)          ; drift towards the player's height
        jr z,.f
        ld a,(py)
        cp (ix+O_Y)
        jr z,.f
        jr c,.up
        inc (ix+O_Y)
        jr .f
.up:    dec (ix+O_Y)
.f:     dec (ix+O_T)
        ret nz
        call rand
        and 31
        add a,30
        ld (ix+O_T),a
        ld a,(ix+O_X)
        cp 40
        ret c
        jp efire

; ground/ceiling gun: rides with the scenery and shoots at the player
u_turr: ld a,(scrolling)
        or a
        jr z,.s
        ld a,(ix+O_X)
        dec a
        cp 2
        jp c,objfree
        ld (ix+O_X),a
.s:     dec (ix+O_T)
        ret nz
        call rand
        and 31
        add a,35
        ld (ix+O_T),a
        ld a,(ix+O_X)
        cp 20
        ret c
        cp 88
        ret nc
        ; fall through

; enemy IX fires a bullet roughly at the player
efire:  ld a,(pstate)
        or a
        ret nz
        call newobj
        ret c
        ld (iy+O_TYPE),T_EBUL
        ld a,(ix+O_X)
        ld (iy+O_X),a
        ld b,0FEh               ; dx = -2, or +2 if the player is behind
        ld a,(px)
        cp (ix+O_X)
        jr c,.l
        ld b,2
.l:     ld (iy+O_A),b
        ld a,(ix+O_Y)
        inc a
        ld (iy+O_Y),a
        ld b,a
        ld a,(py)
        inc a
        sub b                   ; dy to the player
        ld b,0
        jp p,.pos
        cp 0FDh
        jr nc,.set
        ld b,0FFh
        jr .set
.pos:   cp 4
        jr c,.set
        ld b,1
.set:   ld (iy+O_B),b
        ret

u_caps: ld a,(scrolling)        ; drifts with the scenery
        or a
        ret z
        ld a,(ix+O_X)
        dec a
        cp 2
        jp c,objfree
        ld (ix+O_X),a
        ret

u_expl: inc (ix+O_T)
        ld a,(ix+O_T)
        cp 6
        jp nc,objfree
        ld a,(scrolling)
        or a
        ret z
        dec (ix+O_X)
        ret

u_ebul: ld a,(ix+O_X)
        add a,(ix+O_A)
        cp 2
        jp c,objfree
        ld (ix+O_X),a
        ld a,(ix+O_Y)
        add a,(ix+O_B)
        cp 46
        jp nc,objfree
        ld (ix+O_Y),a
        ret

; ---------------------------------------------------------------------------
; enemy waves, started by stage events: a line of 5 sine-wave darts
; (shoot all 5 for a capsule) or 3 spinners (the last, red one carries one)
spawner:
        ld a,(wleft)
        or a
        ret z
        ld hl,wtimer
        dec (hl)
        ret nz
        dec a
        ld (wleft),a
        ld a,(wgap)
        ld (wtimer),a
        call newobj
        ret c
        ld (iy+O_X),94
        ld a,(wtype)
        or a
        jr nz,.spin
        ld (iy+O_TYPE),T_DART
        ld a,(wy)
        ld (iy+O_Y),a
        ld (iy+O_A),a
        ld (iy+O_F),1
        ret
.spin:  ld (iy+O_TYPE),T_SPIN
        call rand
        and 31
        add a,6
        ld (iy+O_Y),a
        ld (iy+O_T),45
        ld a,(wleft)
        or a
        ret nz
        ld (iy+O_F),2           ; last one carries a capsule
        ret

rand:   push bc
        ld a,(seed)
        ld b,a
        add a,a
        add a,a
        add a,b
        inc a
        ld (seed),a
        ld b,a
        ld a,r
        xor b
        pop bc
        ret

; ---------------------------------------------------------------------------
; enemy (IX) destroyed: score, then explosion or capsule
killenemy:
        ld a,(ix+O_TYPE)        ; dart 100, spinner 200, turret 300
        call addscore
        ld hl,SFX_BOOM
        call sfx
        bit 1,(ix+O_F)
        jr nz,.cap
        bit 0,(ix+O_F)
        jr z,.exp
        ld hl,wkills
        inc (hl)
        ld a,(hl)
        cp 5
        jr z,.cap
.exp:   ld (ix+O_TYPE),T_EXPL
        ld (ix+O_T),0
        ret
.cap:   ld (ix+O_TYPE),T_CAPS
        ld (ix+O_F),0
        ret

collide:
        ; ---- player shots against enemies
        ld iy,shots
        ld b,NSHOTS
.s:     push bc
        ld a,(iy+0)
        or a
        jr z,.sn
        ld ix,objs
        ld c,NOBJ
.o:     ld a,(ix+O_TYPE)
        dec a
        cp T_TURR               ; enemy types are 1..T_TURR
        jr nc,.on
        ld d,2                 ; shot x..x+2 (beam x..x+6) against x..x+4
        ld e,7
        ld a,(iy+3)
        or a
        jr z,.k
        ld d,6
        ld e,11
.k:     ld a,(iy+0)
        add a,d
        sub (ix+O_X)
        cp e
        jr nc,.on
        ld a,(iy+1)             ; shot y within enemy y..y+2
        sub (ix+O_Y)
        cp 3
        jr nc,.on
        push bc
        call killenemy
        pop bc
        ld a,(iy+3)
        or a
        jr nz,.on               ; the beam goes straight through
        ld (iy+0),0
        jr .sn
.on:    ld de,OSIZE
        add ix,de
        dec c
        jr nz,.o
.sn:    call vpoll
        pop bc
        ld de,SSIZE
        add iy,de
        djnz .s

        ; ---- missile against enemies
        ld a,(mx)
        or a
        jr z,.pl
        ld ix,objs
        ld b,NOBJ
.m:     ld a,(ix+O_TYPE)
        dec a
        cp T_TURR
        jr nc,.mn
        ld a,(mx)              ; missile 2x2 against enemy 5x3
        inc a
        sub (ix+O_X)
        cp 6
        jr nc,.mn
        ld a,(my)
        inc a
        sub (ix+O_Y)
        cp 4
        jr nc,.mn
        push bc
        call killenemy
        pop bc
        xor a
        ld (mx),a
        jr .pl
.mn:    ld de,OSIZE
        add ix,de
        djnz .m
.pl:    call bosscollide

        ; ---- player against everything
        ld a,(pstate)
        or a
        ret nz
        ld a,(gstate)
        or a
        ret nz
        ld ix,objs
        ld b,NOBJ
.p:     ld a,(ix+O_TYPE)
        or a
        jr z,.pn
        cp T_EXPL
        jr z,.pn
        ld d,9                  ; x overlap range for 5-wide things
        cp T_EBUL
        jr nz,.w
        ld d,6                  ; 2-wide bullet
.w:     ld a,(px)               ; player body x+1..x+5
        add a,5
        sub (ix+O_X)
        cp d
        jr nc,.pn
        ld d,5                  ; 3-tall things
        ld a,(ix+O_TYPE)
        cp T_EBUL
        jr nz,.h
        ld d,3
.h:     ld a,(py)
        add a,2
        sub (ix+O_Y)
        cp d
        jr nc,.pn
        ld a,(ix+O_TYPE)
        cp T_CAPS
        jr z,.cap
        ld a,(invuln)
        or a
        jr nz,.pn
        ld a,(ix+O_TYPE)
        cp T_EBUL
        jr z,.bul
        call killenemy
        jp phit
.bul:   ld (ix+O_TYPE),0
        jp phit
.cap:   ld (ix+O_TYPE),0
        push bc
        ld hl,SFX_CAPS
        call sfx
        ld a,5                  ; 500 points
        call addscore
        ld a,(barpos)
        inc a
        cp 6
        jr c,.b
        xor a
.b:     ld (barpos),a
        call drawbar
        pop bc
.pn:    ld de,OSIZE
        add ix,de
        djnz .p

        ; ---- player against the scenery
        ld a,(invuln)
        or a
        ret nz
        ld a,(px)
        add a,6
        ld b,a
        ld a,(py)
        inc a
        ld c,a
        call solidat            ; nose
        jp nz,pdie
        ld a,(px)
        inc a
        ld b,a
        ld a,(py)
        ld c,a
        call solidat            ; top
        jp nz,pdie
        inc c
        inc c
        call solidat            ; bottom
        jp nz,pdie
        ret

; ===========================================================================
;  drawing
; ===========================================================================
drawall:
        call drawboss
        ld ix,objs
        ld b,NOBJ
.o:     push bc
        ld a,(ix+O_TYPE)
        or a
        call nz,drawobj
        call vpoll
        pop bc
        ld de,OSIZE
        add ix,de
        djnz .o
        call vpoll

        ld iy,shots
        ld b,NSHOTS
.s:     push bc
        ld a,(iy+0)
        or a
        jr z,.sn
        ld b,a
        ld c,(iy+1)
        ld hl,SPR+G_SHOT
        ld e,60h
        ld a,(iy+2)
        or a
        jr z,.ss
        dec c
        ld hl,SPR+G_SHOTU
.ss:    ld a,(iy+3)
        or a
        jr z,.sd
        ld hl,SPR+G_BEAM
        ld e,50h
.sd:    call drawspr
.sn:    pop bc
        ld de,SSIZE
        add iy,de
        djnz .s

        ld a,(mx)
        or a
        jr z,.nm
        ld b,a
        ld a,(my)
        ld c,a
        ld hl,SPR+G_MISS
        ld e,70h
        call drawspr
.nm:

        ld a,(pstate)
        or a
        jr nz,.np
        ld a,(invuln)
        or a
        jr z,.dp
        ld a,(tick)
        and 2
        jr z,.np
.dp:    ld a,(px)
        ld b,a
        ld a,(py)
        ld c,a
        ld hl,SPR+G_SHIP
        ld e,70h
        call drawspr
        ld a,(shield)           ; shield in front of the nose
        or a
        jr z,.nsh
        ld e,50h
        cp 3
        jr nc,.sc
        ld e,70h                ; nearly used up
.sc:    ld a,(px)
        add a,7
        ld b,a
        ld a,(py)
        ld c,a
        ld hl,SPR+G_SHLD
        call drawspr
.nsh:   ld a,(drones)
        or a
        jr z,.np
        ld a,1
        call dronedraw
        ld a,(drones)
        cp 2
        jr c,.np
        ld a,2
        call dronedraw
.np:    ld a,(demo)
        or a
        jr z,.ng
        ld a,(tick)
        and 8
        jr nz,.ng
        ld hl,txt_demo          ; blinking DEMO PLAY near the bottom
        ld de,CBUF+22*40+15
        ld b,22
        call buftext
.ng:    ld a,(banner)           ; STAGE n at the start of a stage
        or a
        jr z,.nb
        dec a
        ld (banner),a
        ld hl,txt_stage
        ld de,CBUF+11*40+16
        ld b,11
        call buftext
        ld a,(stage)
        add a,21h
        ld (CBUF+11*40+22),a
.nb:    ld a,(bstate)
        cp 4
        jr nz,.nc
        ld hl,txt_clear         ; STAGE CLEAR after the boss
        ld de,CBUF+11*40+14
        ld b,11
        call buftext
.nc:    ld a,(gstate)
        or a
        ret z
        ld hl,txt_over          ; GAME OVER across row 11
        ld de,CBUF+11*40+15
        ld b,11
        ; fall through

; ASCII string HL into the buffer at DE (row B), white
buftext:
        push hl
        ld hl,touch
        ld a,l
        add a,b
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld (hl),1
        pop hl
.g:     ld a,(hl)
        or a
        jr z,.gd
        inc hl
        ld c,0                  ; space and punctuation -> blank
        cp '0'
        jr c,.gs
        sub 10h                 ; digits -> 20h..29h
        ld c,a
        cp 31h
        jr c,.gs
        sub 30h                 ; letters -> 01h..1Ah
        ld c,a
.gs:    ld a,c
        ld (de),a
        ld a,d
        add a,4
        ld d,a
        ld a,70h
        ld (de),a
        ld a,d
        sub 4
        ld d,a
        inc de
        jr .g
.gd:    ret

dronedraw: call dronepos
        inc b
        inc b
        ld hl,SPR+G_DRONE
        ld e,20h
        ld a,(tick)
        and 1
        jr z,.dc
        ld e,60h
.dc:    jp drawspr

drawobj:                        ; A = type, IX = object
        ld b,(ix+O_X)
        ld c,(ix+O_Y)
        cp T_DART
        jr nz,.n1
        ld hl,SPR+G_DART
        ld e,50h
        jp drawspr
.n1:    cp T_SPIN
        jr nz,.n2
        ld hl,SPR+G_SPIN0
        bit 2,(ix+O_B)
        jr z,.s0
        ld hl,SPR+G_SPIN1
.s0:    ld e,30h
        bit 1,(ix+O_F)
        jr z,.s1
        ld e,20h
.s1:    jp drawspr
.n2:    cp T_TURR
        jr nz,.n2b
        ld hl,SPR+G_TURF
        bit 2,(ix+O_F)
        jr z,.t0
        ld hl,SPR+G_TURC
.t0:    ld e,40h                ; green
        jp drawspr
.n2b:   cp T_CAPS
        jr nz,.n3
        ld hl,SPR+G_CAPS
        ld e,20h
        ld a,(tick)
        and 2
        jr z,.c1
        ld e,60h
.c1:    jp drawspr
.n3:    cp T_EXPL
        jr nz,.n4
        ld a,(ix+O_T)
        and 6                   ; frame * 2
        rlca
        rlca
        rlca
        rlca                    ; frame * 32
        ld e,a
        ld d,0
        ld hl,SPR+G_EXP0
        add hl,de
        ld e,60h
        cp 64
        jr c,.e1
        ld e,20h
.e1:    jp drawspr
.n4:    ld hl,SPR+G_EBUL
        ld e,70h
        jp drawspr

; ===========================================================================
;  stage: the scenery is built at run time, one character column at a time,
;  into a 256-column ring (CHR0 / CHR1 / COL, row stride 296; columns 0..39
;  are mirrored at 256..295 so the blitter never has to wrap)
; ===========================================================================
startlevel:
        ld hl,objs
        ld b,NOBJ*OSIZE
.c:     ld (hl),0
        inc hl
        djnz .c
        ld hl,shots
        ld b,NSHOTS*SSIZE
.s:     ld (hl),0
        inc hl
        djnz .s
        xor a
        ld (mx),a
        ld (bstate),a
        ld (wleft),a
        ld (seglen),a
        ld (curc),a
        ld (curf),a
        ld (dotx),a
        ld hl,0
        ld (scrollx),hl
        ld (scabs),hl
        ld (genabs),hl
        ld a,1
        ld (scrolling),a
        ld (forceall),a
        ld a,0FFh
        ld (lastcell),a
        ld a,(stage)            ; this stage's terrain, events, colour rows
        ld b,a
        add a,a
        add a,b
        add a,a
        ld e,a
        ld d,0
        ld hl,stagetab
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (lvlptr),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (evptr),de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld (rfptr),de
        ld a,75                 ; STAGE n banner for 3 seconds
        ld (banner),a
        ld hl,colR              ; the column before the first is open sky
        ld (hl),0
        inc hl
        ld (hl),46
        inc hl
        ld (hl),0
        inc hl
        ld (hl),0FFh
        inc hl
        ld (hl),0
        call initstars
        ld b,42                 ; the first screen and a bit
.g:     push bc
        call gencell
        pop bc
        djnz .g
        ret

; keep the map built 42 columns ahead of the left edge of the screen
genmap:
        ld hl,(scabs)
        srl h
        rr l
        ld de,42
        add hl,de
        ld de,(genabs)
        or a
        sbc hl,de
        ret z
        ret c
        ; fall through

; build ring column (genabs & 255): characters for both scroll phases and
; colours, then fire any stage events for that column
gencell:
        ld hl,colR              ; previous right half becomes "P"
        ld de,colP
        ld bc,DSIZE
        ldir
        ld iy,colL
        call nextcol
        ld iy,colR
        call nextcol
        ld a,(genabs)
        ld e,a
        ld d,0
        ld hl,CHR0
        add hl,de
        ld (gp0),hl
        ld hl,COL
        add hl,de
        ld (gpa),hl
        ld a,e
        cp 40
        sbc a,a
        ld (gm0),a              ; FF = also write the mirror copy
        dec e                   ; the odd-phase character belongs to c-1
        ld hl,CHR1
        add hl,de
        ld (gp1),hl
        ld a,e
        cp 40
        sbc a,a
        ld (gm1),a
        ld a,(colL+2)           ; colours for this column's style
        ld b,a
        add a,a
        add a,b
        ld e,a
        ld d,0
        ld hl,attrtab
        add hl,de
        ld (gat),hl
        xor a
        ld (gy),a
        ld b,ROWS
.row:   push bc
        xor a
        ld (gc0),a
        ld (gc1),a
        ld (gcls),a
        ld a,(gy)
        ld c,a
        ld iy,colL              ; top dots
        call dott
        call gclass
        or a
        jr z,.a1
        ld hl,gc0
        set 0,(hl)
        ld hl,gc1
        set 1,(hl)
.a1:    ld iy,colR
        call dott
        call gclass
        or a
        jr z,.a2
        ld hl,gc0
        set 1,(hl)
.a2:    ld iy,colP
        call dott
        or a
        jr z,.a3
        ld hl,gc1
        set 0,(hl)
.a3:    inc c                   ; bottom dots
        ld iy,colL
        call dott
        call gclass
        or a
        jr z,.b1
        ld hl,gc0
        set 2,(hl)
        ld hl,gc1
        set 3,(hl)
.b1:    ld iy,colR
        call dott
        call gclass
        or a
        jr z,.b2
        ld hl,gc0
        set 3,(hl)
.b2:    ld iy,colP
        call dott
        or a
        jr z,.b3
        ld hl,gc1
        set 2,(hl)
.b3:    ld a,(gc0)              ; even-phase character
        or 0F0h
        ld hl,(gp0)
        ld (hl),a
        ld e,a
        ld a,(gm0)
        or a
        jr z,.m0
        inc h
        ld (hl),e
        dec h
.m0:    ld de,STRIDE
        add hl,de
        ld (gp0),hl
        ld a,(gc1)              ; odd-phase character
        or 0F0h
        ld hl,(gp1)
        ld (hl),a
        ld e,a
        ld a,(gm1)
        or a
        jr z,.m1
        inc h
        ld (hl),e
        dec h
.m1:    ld de,STRIDE
        add hl,de
        ld (gp1),hl
        ld hl,(gat)             ; colour
        ld a,(gcls)
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        ld hl,(gpa)
        ld (hl),a
        ld e,a
        ld a,(gm0)
        or a
        jr z,.ma
        inc h
        ld (hl),e
        dec h
.ma:    ld de,STRIDE
        add hl,de
        ld (gpa),hl
        ld hl,gy
        inc (hl)
        inc (hl)
        call vpoll
        pop bc
        dec b
        jp nz,.row
        ld hl,(genabs)
        inc hl
        ld (genabs),hl
        ; fall through

; fire the stage events for the column just built
events:
        ld hl,(evptr)
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(genabs)
        dec hl
        or a
        sbc hl,de
        ret nz
        ld hl,(evptr)
        inc hl
        inc hl
        ld a,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld (evptr),hl
        call .fire
        jr events
.fire:  dec a
        jr z,ev_dart
        dec a
        jr z,ev_spin
        dec a
        jr z,ev_turf
        dec a
        jr z,ev_turc
        jp ev_boss

ev_dart:
        ld a,c
        ld (wy),a
        xor a
        ld (wtype),a
        ld (wkills),a
        ld a,5
        ld (wleft),a
        ld (wgap),a
        ld a,1
        ld (wtimer),a
        ret
ev_spin:
        ld a,1
        ld (wtype),a
        ld (wtimer),a
        ld a,3
        ld (wleft),a
        ld a,22
        ld (wgap),a
        ret
ev_turf:
        call newobj
        ret c
        ld a,(colR+1)           ; sit on the floor
        sub 3
        ld (iy+O_Y),a
        jr ev_tur
ev_turc:
        call newobj
        ret c
        ld a,(colR+0)           ; hang from the ceiling
        ld (iy+O_Y),a
        ld (iy+O_F),4
ev_tur: ld (iy+O_TYPE),T_TURR
        ld (iy+O_X),90
        ld (iy+O_T),25
        ret
ev_boss:
        xor a
        ld (scrolling),a
        ld (bflash),a
        ld (bvol),a
        inc a
        ld (bstate),a
        ld (bdy),a
        ld a,100
        ld (bx),a
        ld a,16
        ld (by),a
        ld a,40
        ld (bfire),a
        ld a,(stage)            ; 24, 30, 36, 42 hits to kill
        add a,a
        ld b,a
        add a,a
        add a,b
        add a,24
        ld (bhp),a
        ld (bhpmax),a
        xor a
        ld (sparkcool),a
        ; fall through

; bfrac = boss health in sixteenths (for the bar and the core colour)
bossfrac:                       ; preserves BC, DE
        push bc
        push de
        ld a,(bhp)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(bhpmax)
        ld e,a
        ld d,0
        ld b,0
.l:     or a
        sbc hl,de
        jr c,.d
        inc b
        jr .l
.d:     ld a,b
        ld (bfrac),a
        pop de
        pop bc
        ret

; class = max(class, E), preserves A
gclass: push af
        ld a,(gcls)
        cp e
        jr nc,.k
        ld a,e
        ld (gcls),a
.k:     pop af
        ret

; next dot column of the stage into descriptor IY
nextcol:
        ld a,(seglen)
        or a
        jr nz,.go
        ld hl,(lvlptr)
        ld a,(hl)
        or a
        jr nz,.ld
        ld a,255                ; end of the stage: hold the last heights
        ld (seglen),a
        jr .go
.ld:    ld (seglen),a
        inc hl
        ld a,(hl)
        ld (tgc),a
        inc hl
        ld a,(hl)
        ld (tgf),a
        inc hl
        ld a,(hl)
        ld (style),a
        inc hl
        ld (lvlptr),hl
.go:    ld hl,seglen
        dec (hl)
        ld hl,curc
        ld a,(tgc)
        call .toward
        ld hl,curf
        ld a,(tgf)
        call .toward
        ld a,(curc)
        ld (iy+0),a
        ld a,(curf)
        ld b,a
        ld a,46
        sub b
        ld (iy+1),a
        ld a,(style)
        ld (iy+2),a
        ld (iy+3),0FFh
        call rand
        and 31
        jr nz,.ns
        call rand
        and 31
        add a,7
        ld (iy+3),a             ; a star
.ns:    ld hl,dotx
        inc (hl)
        ld a,(hl)
        ld (iy+4),a
        ret
.toward:
        cp (hl)
        ret z
        jr c,.dn
        inc (hl)
        ret
.dn:    dec (hl)
        ret

; dot at y = C in column IY: A = 1 if lit, E = 0 sky / 1 surface / 2 deep
dott:   ld a,c
        cp (iy+0)
        jr nc,.nc
        ld a,(iy+0)             ; ceiling: depth = h - 1 - y
        dec a
        sub c
        jr .solid
.nc:    cp (iy+1)
        jr c,.sky
        sub (iy+1)              ; floor: depth = y - y0
.solid: ld e,1
        cp 3
        jr c,.sk
        ld e,2
.sk:    cp 2
        jr c,.lit               ; 2-dot solid skin
        ld a,(iy+2)
        or a
        jr z,.rock
        dec a
        jr z,.fort
        dec a
        jr nz,.hive
        ld a,(iy+4)             ; crystal: diagonal stripes
        sub c
        and 3
        jr z,.lit
        xor a
        ret
.hive:  ld a,(iy+4)             ; hive: 2x2 blobs
        xor c
        and 2
        jr z,.lit
        xor a
        ret
.rock:  ld a,c                  ; rock: checkerboard
        add a,(iy+4)
        and 1
        jr z,.lit
        xor a
        ret
.fort:  ld a,c                  ; fortress: panel lines
        and 3
        jr z,.lit
        ld a,(iy+4)
        and 7
        jr z,.lit
        xor a
        ret
.lit:   ld a,1
        ret
.sky:   ld e,0
        cp (iy+3)
        ld a,1
        ret z
        xor a
        ret

attrtab: DB 70h,60h,20h         ; rock: sky, yellow surface, red depths
         DB 70h,71h,51h         ; fortress: white / cyan on blue
         DB 70h,50h,30h         ; crystal: cyan surface, magenta depths
         DB 70h,40h,64h         ; hive: green surface, yellow on green depths

; ===========================================================================
;  parallax starfield: a far layer at half speed (every 4th star twinkles)
;  and a few fast streaks, drawn as single dots into open sky only.  Sky
;  cells are already white on black, so only characters change.
; ===========================================================================
STARS   EQU 24                  ; far stars: x in half dots (0..159)
FAST    EQU 6                   ; streaks: x in dots (0..79)

initstars:
        ld hl,farx
        ld b,STARS
.f:     call rand
        cp 160
        jr c,.f1
        sub 96
.f1:    ld (hl),a
        inc hl
        djnz .f
        ld b,STARS
        call .ys
        ld hl,fastx
        ld b,FAST
.s:     call rand
        and 127
        cp 80
        jr c,.s1
        sub 48
.s1:    ld (hl),a
        inc hl
        djnz .s
        ld b,FAST
.ys:    call randy              ; B random heights at HL
        ld (hl),a
        inc hl
        djnz .ys
        ret

randy:  call rand               ; A = random dot y, 0..45
        and 63
        cp 46
        ret c
        sub 32
        ret

updstars:
        ld hl,farx
        ld b,STARS
.f:     ld a,(hl)
        sub 1                   ; half a dot per tick
        jr nc,.f1
        push hl                 ; off the left: back in on the right
        ld de,STARS
        add hl,de
        call randy
        ld (hl),a
        pop hl
        ld a,159
.f1:    ld (hl),a
        inc hl
        djnz .f
        ld hl,fastx
        ld b,FAST
.s:     ld a,(hl)
        sub 2                   ; two dots per tick
        jr nc,.s1
        push hl
        ld de,FAST
        add hl,de
        call randy
        ld (hl),a
        pop hl
        ld a,79
.s1:    ld (hl),a
        inc hl
        djnz .s
        ret

drawstars:
        ld ix,farx
        ld b,STARS
.f:     ld a,b
        and 3
        jr nz,.vis
        ld a,(tick)             ; twinkle
        add a,b
        and 16
        jr nz,.nx
.vis:   ld a,(ix+0)
        srl a
        ld c,(ix+STARS)
        call plotstar
.nx:    inc ix
        djnz .f
        call vpoll
        ld ix,fastx
        ld b,FAST
.s:     ld a,(ix+0)
        ld c,(ix+FAST)
        call plotstar
        inc ix
        djnz .s
        ret

; one dot at x = A, y = C into the buffer, if that cell is open sky.
; Preserves B, IX.
plotstar:
        ld d,a
        ld a,c
        and 1
        add a,a
        ld e,a
        ld a,d
        and 1
        or e
        ld e,a                  ; E = quarter-block bit number
        push bc
        ld a,c
        and 0FEh                ; row * 2
        ld l,a
        ld h,0
        ld bc,row40
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,d
        srl a
        ld c,a
        ld b,0
        add hl,bc
        ld bc,CBUF
        add hl,bc               ; HL = character in the buffer
        ld a,h
        add a,4                 ; its colour
        ld h,a
        ld a,(hl)
        cp 70h                  ; open sky only (stars go behind scenery)
        jr nz,.no
        ld a,h
        sub 4
        ld h,a
        push hl
        ld hl,masktab
        ld a,e
        add a,l
        ld l,a
        adc a,h
        sub l
        ld h,a
        ld a,(hl)
        pop hl
        or (hl)
        ld (hl),a
.no:    pop bc
        ret

masktab: DB 1,2,4,8

; ===========================================================================
;  boss
;  bstate 1 = arriving, 2 = fighting, 3 = blowing up, 4 = STAGE CLEAR
; ===========================================================================
updboss:
        ld a,(bstate)
        or a
        ret z
        dec a
        jr z,.enter
        dec a
        jr z,.fight
        dec a
        jp z,.dying
        ld hl,btimer            ; stage clear: on to the next stage
        dec (hl)
        ret nz
        ld a,(stage)
        inc a
        cp 5
        jr c,.ns
        ld hl,loopn             ; after stage 5, round again, harder
        inc (hl)
        xor a
.ns:    ld (stage),a
        jp startlevel
.enter: ld hl,bx
        dec (hl)
        ld a,(hl)
        cp 62
        ret nz
        ld a,2
        ld (bstate),a
        ret
.fight: ld a,(bflash)
        or a
        jr z,.nf
        dec a
        ld (bflash),a
.nf:    ld a,(sparkcool)
        or a
        jr z,.nk
        dec a
        ld (sparkcool),a
.nk:    ld a,(bfrac)            ; badly damaged: smoking
        cp 6
        jr nc,.nsm
        ld a,(tick)
        and 7
        call z,bossboom
.nsm:   ld a,(tick)             ; up and down
        and 1
        jr nz,.nm
        ld hl,bdy
        ld a,(by)
        add a,(hl)
        ld (by),a
        cp 4
        jr c,.flip
        cp 28
        jr c,.nm
.flip:  ld a,(hl)
        neg
        ld (hl),a
.nm:    ld hl,bfire
        dec (hl)
        ret nz
        ld a,(loopn)            ; fires faster each stage and each round
        add a,a
        ld b,a
        ld a,(stage)
        add a,b
        add a,a
        ld b,a
        ld a,30
        sub b
        jr c,.min
        cp 12
        jr nc,.r
.min:   ld a,12
.r:     ld (hl),a
        ld a,(bx)               ; a fan of three from the mouth
        ld b,a
        ld a,(by)
        add a,6
        ld c,a
        ld d,0FFh
        call bshot
        ld d,0
        call bshot
        ld d,1
        call bshot
        ld hl,bvol              ; and the claw tips every other volley
        inc (hl)
        bit 0,(hl)
        ret z
        ld a,(by)
        ld c,a
        ld d,0
        call bshot
        ld a,(by)
        add a,13
        ld c,a
        jp bshot
.dying: ld hl,btimer
        dec (hl)
        jr z,.clear
        ld a,(hl)
        and 3
        ret nz
        call bossboom           ; explosions all over it
        ld hl,SFX_BOOM
        jp sfx
.clear: ld a,4
        ld (bstate),a
        ld a,100
        ld (btimer),a
        ld a,50h                ; 10000 bonus
        call addscore
        ld a,50h
        jp addscore

; an explosion somewhere on the boss's body
bossboom:
        call newobj
        ret c
        ld (iy+O_TYPE),T_EXPL
        call rand
        and 15
        ld b,a
        ld a,(bx)
        add a,b
        ld (iy+O_X),a
        call rand
        and 15
        ld b,a
        ld a,(by)
        add a,b
        ld (iy+O_Y),a
        ret

; boss bullet at B, C with dy = D.  Preserves BC, DE.
bshot:  push bc
        push de
        call newobj
        pop de
        pop bc
        ret c
        ld (iy+O_TYPE),T_EBUL
        ld (iy+O_X),b
        ld (iy+O_Y),c
        ld (iy+O_A),0FEh
        ld (iy+O_B),d
        ret

; core hit (only while fighting)
bosshit:
        ld a,(bstate)
        cp 2
        ret nz
        ld a,2
        ld (bflash),a
        ld hl,SFX_CLANK
        call sfx
        ld hl,bhp
        dec (hl)
        push af
        call bossfrac
        pop af
        ret nz
        ld a,3
        ld (bstate),a
        ld a,60
        ld (btimer),a
        ld hl,SFX_DEATH
        jp sfx

; shots and missile against the boss (armour absorbs, the core takes damage),
; and the player against its body
bosscollide:
        ld a,(bstate)
        or a
        ret z
        cp 3
        ret nc
        ld iy,shots
        ld b,NSHOTS
.s:     ld a,(iy+0)
        or a
        jr z,.sn
        ld c,2
        ld a,(iy+3)
        or a
        jr z,.k
        ld c,6
.k:     ld a,(iy+0)
        add a,c
        ld hl,bx
        sub (hl)                ; x offset into the body
        cp 21
        jr nc,.sn
        ld e,a
        ld a,(iy+1)
        ld hl,by
        sub (hl)                ; y offset
        cp 15
        jr nc,.sn
        ld (iy+0),0             ; absorbed
        ld d,a                  ; D = y offset, E = x offset
        call .core
        jr nc,.arm
        call bosshit
        jr .sn
.arm:   ld a,(sparkcool)        ; glanced off the armour: a spark
        or a
        jr nz,.sn
        ld a,3
        ld (sparkcool),a
        ld a,(bx)
        add a,e
        sub 3
        ld h,a
        ld a,(by)
        add a,d
        dec a
        ld l,a
        push bc
        push iy
        call newobj
        jr c,.nsp
        ld (iy+O_TYPE),T_EXPL
        ld (iy+O_T),2           ; start half-way: a short flash
        ld (iy+O_X),h
        ld (iy+O_Y),l
.nsp:   pop iy
        pop bc
.sn:    ld de,SSIZE
        add iy,de
        djnz .s
        ld a,(mx)               ; missile
        or a
        jr z,.pl
        inc a
        ld hl,bx
        sub (hl)
        cp 21
        jr nc,.pl
        ld e,a
        ld a,(my)
        inc a
        ld hl,by
        sub (hl)
        cp 15
        jr nc,.pl
        xor a
        ld (mx),a
        ld a,(my)
        inc a
        ld hl,by
        sub (hl)
        call .core
        jr nc,.pl
        call bosshit            ; missiles do double damage
        call bosshit
.pl:    ld a,(pstate)
        or a
        ret nz
        ld a,(invuln)
        or a
        ret nz
        ld a,(bx)               ; player x+1..x+5 against bx+2..bx+20
        add a,2
        ld b,a
        ld a,(px)
        add a,5
        sub b
        cp 23
        ret nc
        ld a,(by)               ; player y..y+2 against by+2..by+12
        add a,2
        ld b,a
        ld a,(py)
        add a,2
        sub b
        cp 13
        ret nc
        jp pdie
; A = y offset, E = x offset: carry if inside the core
.core:  cp 4                    ; core area: x 6..15, y 4..10
        jr c,.no
        cp 11
        jr nc,.no
        ld a,e
        cp 6
        jr c,.no
        cp 16
        ret                     ; carry = inside
.no:    or a
        ret

drawboss:
        ld a,(bstate)
        or a
        ret z
        cp 4
        ret z
        cp 3
        jr nz,.d
        ld a,(btimer)           ; blowing up: flicker, then gone
        cp 30
        ret c
        ld a,(tick)
        and 1
        ret z
.d:     ld a,(stage)            ; this stage's colours
        ld b,a
        add a,a
        add a,a
        add a,a
        add a,a
        sub b                   ; * 15
        ld e,a
        ld d,0
        ld hl,bosscol
        add hl,de
        ld (bpal),hl
        xor a
        ld (bi),a
        ld (bcx),a
        ld a,(bx)
        ld (btx),a
        ld a,(by)
        ld (bty),a
.t:     ld a,(bi)
        ld e,a
        ld d,0
        ld hl,(bpal)
        add hl,de
        ld e,(hl)
        cp 7                    ; the core: colour shows its health
        jr nz,.nc
        ld a,(bfrac)
        ld e,30h                ; magenta: healthy
        cp 11
        jr nc,.nc2
        ld e,20h                ; red: hurt
        cp 6
        jr nc,.nc2
        ld e,60h                ; yellow: badly hurt
        cp 3
        jr nc,.nc2
        ld a,(tick)             ; nearly dead: flashing yellow / red
        and 2
        jr z,.nc2
        ld e,20h
.nc2:   ld a,(bflash)           ; white flash on every hit
        or a
        jr z,.nc
        ld e,70h
.nc:    ld a,(bi)
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,SPR+G_BOSS0
        add hl,bc
        ld a,(btx)
        ld b,a
        ld a,(bty)
        ld c,a
        call drawspr
        call vpoll
        ld a,(btx)
        add a,7
        ld (btx),a
        ld hl,bcx
        inc (hl)
        ld a,(hl)
        cp 3
        jr nz,.n
        ld (hl),0
        ld a,(bx)
        ld (btx),a
        ld a,(bty)
        add a,3
        ld (bty),a
.n:     ld hl,bi
        inc (hl)
        ld a,(hl)
        cp 15
        jr nz,.t
        ret

; ===========================================================================
;  sound: one square-wave voice on 8253 counter 0 (1.1088 MHz on PAL units)
;
;  Timing comes from 8253 counter 1, which counts TV scanlines (~15.6 kHz),
;  so effects run at the same speed however busy the game is.  sndfast is
;  called from vpoll (dozens of places per tick, and continuously while
;  waiting); every 64 scanlines (~4 ms) the effect takes one step.
;
;  An effect is a priority byte followed by segments of 8 bytes:
;    DW start divider (0 = carry on from the current pitch)
;    DW change per step (signed; bigger divider = lower pitch)
;    DB steps (0 = end of effect)
;    DW noise mask (random 0..mask added to the divider on every update)
;    DB flags (bit 0 = crackle: speaker switched on/off at random)
;  A new effect only interrupts one of equal or lower priority.
; ===========================================================================
SNDT    EQU 0E005h              ; 8253 counter 1 (scanline clock)
STEP    EQU 64                  ; scanlines per effect step

sndinit:
        ld a,74h                ; counter 1: LSB/MSB, mode 2, count 65536
        ld (SNDM),a
        xor a
        ld (SNDT),a
        ld (SNDT),a
        ; fall through
sndstop:
        xor a
        ld (sfxsteps),a
        ld (sfxpri),a
        ld (SNDG),a
        ret

; start effect HL.  Preserves BC, DE.
sfx:    ld a,(sfxpri)
        cp (hl)
        jr c,.ok
        jr z,.ok
        ret
.ok:    push de
        ld a,(hl)
        ld (sfxpri),a
        inc hl
        ld a,36h                ; counter 0: LSB/MSB, square wave
        ld (SNDM),a
        ld de,0
        ld (sndacc),de
        call loadseg
        pop de
        ret

; load the segment at HL, start its pitch.  Ends the effect at steps = 0.
loadseg:
        push hl
        ld de,4
        add hl,de
        ld a,(hl)
        pop hl
        or a
        jr z,sndstop
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or e
        jr z,.keep
        ld (sfxd),de
.keep:  ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (sfxdelta),de
        ld a,(hl)
        inc hl
        ld (sfxsteps),a
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (sfxjm),de
        ld a,(hl)
        inc hl
        ld (sfxflags),a
        ld (sfxseg),hl
        ld hl,(sfxd)
        ld a,l
        ld (SNDC),a
        ld a,h
        ld (SNDC),a
        ld a,1
        ld (SNDG),a
        ret

; advance the sound by the scanlines elapsed since the last call
sndfast:
        push af
        push bc
        push de
        push hl
        ld a,40h                ; latch counter 1
        ld (SNDM),a
        ld a,(SNDT)
        ld e,a
        ld a,(SNDT)
        ld d,a
        ld hl,(sndlast)
        ld (sndlast),de
        or a
        sbc hl,de               ; HL = scanlines elapsed (counter runs down)
        ld a,h
        or l
        jr z,.zero
        xor a
        ld (sndzero),a
        jr .tick
.zero:  ld a,(sndfall)          ; counter never moves (emulator)? fake it
        or a
        jr nz,.fake
        ld hl,sndzero
        inc (hl)
        jr nz,.tick
        ld a,1
        ld (sndfall),a
.fake:  ld hl,3
.tick:  ld a,(sfxsteps)
        or a
        jr z,.out
        ld de,(sndacc)
        add hl,de
        ld b,0                  ; B = 1 if the pitch moved
.step:  ld a,h
        or a
        jr nz,.do
        ld a,l
        cp STEP
        jr c,.done
.do:    ld de,-STEP
        add hl,de
        push hl
        ld hl,(sfxd)
        ld de,(sfxdelta)
        add hl,de
        ld (sfxd),hl
        ld b,1
        ld hl,sfxsteps
        dec (hl)
        jr nz,.more
        ld hl,(sfxseg)
        call loadseg
        ld a,(sfxsteps)
        or a
        jr nz,.more
        pop hl
        jr .out                 ; effect finished
.more:  pop hl
        jr .step
.done:  ld (sndacc),hl
        ld de,(sfxjm)
        ld a,d
        or e
        jr nz,.jit
        ld a,b
        or a
        jr z,.gate
        ld hl,(sfxd)
        jr .wr
.jit:   call rnd16              ; noise: jitter the divider
        ld a,h
        and d
        ld h,a
        ld a,l
        and e
        ld l,a
        ld de,(sfxd)
        add hl,de
.wr:    ld a,l
        ld (SNDC),a
        ld a,h
        ld (SNDC),a
.gate:  ld a,(sfxflags)
        and 1
        jr z,.out
        call rnd16              ; crackle
        ld a,l
        and 1
        ld (SNDG),a
.out:   pop hl
        pop de
        pop bc
        pop af
        ret

rnd16:  ld hl,(rs16)            ; 16-bit Galois LFSR
        srl h
        rr l
        jr nc,.n
        ld a,h
        xor 0B4h
        ld h,a
.n:     ld (rs16),hl
        ret

; Divider -> pitch: 1108800 / divider Hz (0080h = 8.7 kHz, 0400h = 1.1 kHz)
SFX_SHOT:  DB 1                 ; hissing squirt, falling
           DW 0060h,0012h
           DB 18
           DW 003Fh
           DB 0
           DW 0,0
           DB 0
SFX_BOOM:  DB 2                 ; noise bang that drops and crackles out
           DW 0300h,0018h
           DB 40
           DW 03FFh
           DB 0
           DW 0,0030h
           DB 45
           DW 0FFFh
           DB 1
           DW 0,0
           DB 0
SFX_CLANK: DB 2                 ; shield hit
           DW 0090h,0004h
           DB 12
           DW 001Fh
           DB 0
           DW 0200h,0010h
           DB 12
           DW 00FFh
           DB 1
           DW 0,0
           DB 0
SFX_CAPS:  DB 3                 ; bright chime
           DW 0300h,0FFF0h
           DB 10
           DW 0
           DB 0
           DW 01C0h,0FFF8h
           DB 10
           DW 0
           DB 0
           DW 0130h,0
           DB 20
           DW 0
           DB 0
           DW 0,0
           DB 0
SFX_POWER: DB 4                 ; rising sweep and fanfare
           DW 0900h,0FFE0h
           DB 60
           DW 0
           DB 0
           DW 0180h,0
           DB 12
           DW 0
           DB 0
           DW 0120h,0
           DB 12
           DW 0
           DB 0
           DW 00E0h,0
           DB 30
           DW 0
           DB 0
           DW 0,0
           DB 0
SFX_DEATH: DB 5                 ; big, long explosion
           DW 0200h,0010h
           DB 90
           DW 07FFh
           DB 0
           DW 0,0020h
           DB 90
           DW 1FFFh
           DB 0
           DW 0,0040h
           DB 70
           DW 1FFFh
           DB 1
           DW 0,0
           DB 0

; ===========================================================================
;  text
; ===========================================================================
; print 0-terminated ASCII string HL at screen DE with attribute C
print:
        ld a,(hl)
        or a
        ret z
        inc hl
        cp 'A'
        jr c,.nl
        sub 40h
        jr .put
.nl:    cp '0'
        jr c,.sp
        sub 10h
        jr .put
.sp:    xor a
.put:   ld (de),a
        set 3,d
        ld a,c
        ld (de),a
        res 3,d
        inc de
        jr print

txt_1p:   DB "1P",0
txt_hi:   DB "HI",0
txt_mz:   DB "MZ700",0
txt_bar:  DB " SPEED MISSL SPRED BEAM  DRONE  SHLD   ",0
txt_over: DB "GAME OVER",0
txt_demo: DB "DEMO PLAY",0
txt_clear: DB "STAGE CLEAR",0
txt_stage: DB "STAGE",0
txt_tm:   DB "STAGE 1   T LIVES 3     I INVINCIBLE NO ",0
txt_inf:  DB "INF"
txt_yes:  DB "YES"
logocyc:  DB 60h,60h,20h,20h,30h,30h,20h,60h
slots:    DB 1,5, 7,5, 13,5, 19,4, 25,5, 32,4

; ---------------------------------------------------------------------------
; initialised variables
scrollx:  DW 0
hiscore:  DB 05h,00h,00h        ; 050000
vprev:    DB 80h
seed:     DB 7
rs16:     DW 0ACE1h
pworst:   DW 0FFFFh
lastcell: DB 0FFh

        INCLUDE "../build/tables.inc"
SPR:      INCBIN "../build/sprites.bin"
TITLE:    INCBIN "../build/title.bin"
        INCLUDE "../build/stage.inc"
progend:

; ---------------------------------------------------------------------------
; uninitialised memory (cleared at start, not stored in the .MZT)
        ALIGN 256
CBUF:     DS 400h               ; characters (920 used)
ABUF:     DS 400h               ; colours, must be CBUF + 400h
CHR0:     DS BLOCK              ; scenery ring: characters, even dot offset
CHR1:     DS BLOCK              ;   characters, odd dot offset
COL:      DS BLOCK              ;   colours
bss:
scabs:    DS 2                  ; dots scrolled since the stage began
genabs:   DS 2                  ; next scenery column to build
scrolling: DS 1
lvlptr:   DS 2
evptr:    DS 2
seglen:   DS 1
tgc:      DS 1
tgf:      DS 1
style:    DS 1
curc:     DS 1
curf:     DS 1
dotx:     DS 1
colP:     DS DSIZE
colL:     DS DSIZE
colR:     DS DSIZE
gp0:      DS 2
gp1:      DS 2
gpa:      DS 2
gat:      DS 2
gm0:      DS 1
gm1:      DS 1
gy:       DS 1
gc0:      DS 1
gc1:      DS 1
gcls:     DS 1
bstate:   DS 1
bx:       DS 1
by:       DS 1
bdy:      DS 1
bhp:      DS 1
bflash:   DS 1
btimer:   DS 1
bfire:    DS 1
bvol:     DS 1
bi:       DS 1
bcx:      DS 1
btx:      DS 1
bty:      DS 1
loopn:    DS 1
stage:    DS 1                  ; 0..3
stage0:   DS 1                  ; stage the game started on
rfptr:    DS 2                  ; this stage's colour-row flags
banner:   DS 1
bpal:     DS 2
farx:     DS STARS              ; far stars (fary must follow farx)
fary:     DS STARS
fastx:    DS FAST               ; streaks (fasty must follow fastx)
fasty:    DS FAST
bhpmax:   DS 1
bfrac:    DS 1                  ; boss health in sixteenths
sparkcool: DS 1
tsel:     DS 1                  ; trainer menu: start stage
tinf:     DS 1                  ;   infinite lives
tinv:     DS 1                  ;   invincible
inf:      DS 1                  ; ... as in force for this game
inv:      DS 1
tkeys:    DS 1
tmbuf:    DS 41
vcount:   DS 1
tick:     DS 1
pcount:   DS 1
shworst:  DS 2
cellchg:  DS 1
forceall: DS 1
touch:    DS ROWS
ptouch:   DS ROWS
dirty:    DS ROWS
ds_gfx:   DS 2
ds_col:   DS 1
ds_row:   DS 1
ds_n:     DS 1
joy:      DS 1
joynew:   DS 1
gstate:   DS 1
gtimer:   DS 1
pstate:   DS 1
ptimer:   DS 1
px:       DS 1
py:       DS 1
pspeed:   DS 1
invuln:   DS 1
cool:     DS 1
spread:   DS 1
barpos:   DS 1
lives:    DS 1
score:    DS 3
wtimer:   DS 1
wleft:    DS 1
wgap:     DS 1
wtype:    DS 1
wy:       DS 1
wkills:   DS 1
beam:     DS 1
hasmiss:  DS 1
drones:   DS 1
shield:   DS 1
mx:       DS 1
my:       DS 1
thead:    DS 1
trailx:   DS 32
traily:   DS 32
sfxpri:   DS 1
sfxsteps: DS 1
sfxd:     DS 2
sfxdelta: DS 2
sfxjm:    DS 2
sfxflags: DS 1
sfxseg:   DS 2
sndacc:   DS 2
sndlast:  DS 2
sndzero:  DS 1
sndfall:  DS 1
demo:     DS 1
dtimer:   DS 2
ttimer:   DS 2
tkey:     DS 1
cycpos:   DS 1
aijoy:    DS 1
shots:    DS NSHOTS*SSIZE
objs:     DS NOBJ*OSIZE
bss_end:

        ASSERT bss_end < 0D000h
        ASSERT ABUF == CBUF+400h
        SAVEBIN "build/gradiumz.bin", start, progend-start
