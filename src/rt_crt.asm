// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// rt_crt.asm - runtime routines of the Crt unit (included inside runtime.asm)
// =====================================================================================
//
// Screen and keyboard routines in the style of Turbo Pascal's Crt unit. They only use KERNAL calls
// ($FFxx jump table, the same on the C64, C128 and Plus/4) plus the colour/keyboard locations that
// memmap.asm gives per machine, so the same code serves every machine.
//
//   ClrScr, ClrEol, GotoXY(x, y), WhereX, WhereY      screen positions start at 1, as in Turbo Pascal
//   TextColor(c), TextBackground(c)                   Turbo Pascal colour numbers 0..15
//   HighVideo, LowVideo, NormVideo                    (light / dim / normal text colour)
//   ReadKey, KeyPressed, Delay(ms)
//
// ReadKey returns an extended key (cursor keys, function keys, Home) as 0 followed by a scan code in
// the next call, with the PC scan codes that Turbo Pascal programs expect: Up 72, Down 80, Left 75,
// Right 77, Home 71, F1..F8 59..66. DEL returns 8.


rt_clrscr:
    lda #147
    jmp K_CHROUT

rt_gotoxy:              // GotoXY(x, y): x on the stack, y in ac
    jsr popt
    ldx ac              // row = y - 1
    dex
    ldy tmp             // column = x - 1
    dey
    clc
    jmp K_PLOT

rt_wherex:              // ac = column (1 = leftmost)
    sec
    jsr K_PLOT
    iny
    sty ac
    lda #0
    sta ac+1
    rts

rt_wherey:              // ac = row (1 = top)
    sec
    jsr K_PLOT
    inx
    stx ac
    lda #0
    sta ac+1
    rts

rt_clreol:              // clear from the cursor to the end of the line; the cursor stays where it is
    sec
    jsr K_PLOT
    stx sn              // sn = row
    sty sm              // sm = column
    jsr K_SCREEN        // x = number of columns, y = number of rows
    stx sc              // sc = columns
    dey
    cpy sn              // on the bottom row the last cell cannot be written without scrolling
    bne ce_full
    dec sc
ce_full:
    lda sm
    cmp sc
    bcs ce_back
    lda sc
    sec
    sbc sm
    tax                 // characters to blank
ce_loop:
    lda #' '
    jsr K_CHROUT
    dex
    bne ce_loop
ce_back:
    ldx sn              // put the cursor back
    ldy sm
    clc
    jmp K_PLOT

rt_textcolor:           // TextColor(c): print the colour code of the machine for Turbo Pascal colour c
    lda ac
    and #15
    tax
    lda crt_fg,x
    jmp K_CHROUT

rt_textbg:              // TextBackground(c): set the background colour register
    lda ac
    and #15
    tax
    lda crt_bg,x
    sta BG_REG
    rts

rt_highvideo:           // light text colour
    lda #15
    sta ac
    jmp rt_textcolor
rt_lowvideo:            // dim text colour
    lda #8
    sta ac
    jmp rt_textcolor
rt_normvideo:           // normal text colour
    lda #7
    sta ac
    jmp rt_textcolor

rt_keypressed:          // ac = 1 if a key is waiting, else 0
    lda #0
    sta ac+1
    lda rt_keyext
    bne kp_yes
    lda KEYCOUNT
    bne kp_yes
    lda #0
    sta ac
    rts
kp_yes:
    lda #1
    sta ac
    rts

rt_readkey:             // ac = key (waits for one); extended keys deliver 0, then a scan code
    lda #0
    sta ac+1
    lda rt_keyext
    beq rk_wait
    sta ac              // second half of an extended key
    lda #0
    sta rt_keyext
    rts
rk_wait:
    jsr K_GETIN
    beq rk_wait
    ldx #0
rk_find:                // extended key?
    cmp keytab,x
    beq rk_ext
    inx
    inx
    ldy keytab,x
    bne rk_find
    cmp #$14            // DEL key -> backspace
    bne rk_conv
    lda #8
    sta ac
    rts
rk_conv:
    jsr p2a
    sta ac
    rts
rk_ext:
    lda keytab+1,x
    sta rt_keyext
    lda #0
    sta ac
    rts

keytab:                 // PETSCII code, scan code
    .byte $91, 72       // cursor up
    .byte $11, 80       // cursor down
    .byte $9d, 75       // cursor left
    .byte $1d, 77       // cursor right
    .byte $13, 71       // home
    .byte $85, 59       // F1
    .byte $89, 60       // F2
    .byte $86, 61       // F3
    .byte $8a, 62       // F4
    .byte $87, 63       // F5
    .byte $8b, 64       // F6
    .byte $88, 65       // F7
    .byte $8c, 66       // F8
    .byte 0, 0

rt_delay:               // Delay(ms): about ms/17 jiffies of the 60 Hz KERNAL clock
    lsr ac+1
    ror ac
    lsr ac+1
    ror ac
    lsr ac+1
    ror ac
    lsr ac+1
    ror ac
dl_next:
    lda ac
    ora ac+1
    beq dl_done
    jsr K_RDTIM         // a = low byte of the jiffy clock
    sta sn
dl_wait:
    jsr K_RDTIM
    cmp sn
    beq dl_wait         // wait for the next tick
    lda ac
    bne !+
    dec ac+1
!:  dec ac
    jmp dl_next
dl_done:
    rts

// colour tables, indexed by the Turbo Pascal colour number:
//  0 black, 1 blue, 2 green, 3 cyan, 4 red, 5 magenta, 6 brown, 7 light gray,
//  8 dark gray, 9 light blue, 10 light green, 11 light cyan, 12 light red, 13 light magenta,
//  14 yellow, 15 white
#if PLUS4
crt_fg:                 // PETSCII colour codes (Plus/4)
    .byte $90, $1f, $1e, $9f, $1c, $9c, $95, $05, $9a, $99, $9b, $98, $97, $97, $9e, $05
crt_bg:                 // TED colour values: luminance * 16 + hue
    .byte $00, $46, $45, $43, $42, $44, $49, $51, $21, $66, $6f, $63, $62, $64, $67, $71
#else
crt_fg:                 // PETSCII colour codes (C64 / C128)
    .byte $90, $1f, $1e, $9f, $1c, $9c, $95, $9b, $97, $9a, $99, $9f, $96, $9c, $9e, $05
crt_bg:                 // VIC-II colour numbers
    .byte 0, 6, 5, 3, 2, 4, 9, 15, 11, 14, 13, 3, 10, 4, 7, 1
#endif
