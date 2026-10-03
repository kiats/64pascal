// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// editor.asm - the full-screen text editor of the IDE
// =====================================================================================
//
// TEXT BUFFER. The text is kept in a GAP BUFFER between SRC_BASE and SRC_LIMIT: the characters
// before the cursor are at SRC_BASE .. gs-1, those after the cursor at ge .. SRC_LIMIT-1, and the free
// space (the gap) lies between them. The cursor IS the start of the gap, so typing just stores a
// character at gs. Moving the cursor moves characters across the gap one at a time (move_left /
// move_right). Lines end with a line feed ($0A), as the compiler expects; before a compile the gap is
// moved to the end so the text is contiguous.
//
// SCREEN. 24 text rows (0..23) and a status line (row 24) of the 40 column screen are written directly
// into screen RAM. 'topoff' is the offset (from SRC_BASE) of the first character shown, 'leftcol' the
// first visible column of long lines. Each key press redraws the whole screen.
//
// Zero page: gs, ge, ep, scr, tp, et1..et4 (zp.asm) are scratch while editing; they share locations
// with the compiler, so the IDE saves gs and ge in RAM around a compile or run.

.const LF        = $0a
.const TEXT_ROWS = 24
.const STATUS_ROW = SCRN_BASE + 24 * 40

// ---- starting a new text ------------------------------------------------------------------------------
ed_new:
    lda #<SRC_BASE
    sta gs
    lda #>SRC_BASE
    sta gs+1
    lda #<SRC_LIMIT
    sta ge
    lda #>SRC_LIMIT
    sta ge+1
    lda #0
    sta topoff
    sta topoff+1
    sta leftcol
    sta modified
    lda #1
    sta curline
    lda #0
    sta curline+1
    rts

// ---- the gap: moving the cursor one character ---------------------------------------------------------------
// move_left: cursor one character to the left. Carry set = already at the start of the text.
move_left:
    lda gs
    cmp #<SRC_BASE
    bne ml_ok
    lda gs+1
    cmp #>SRC_BASE
    bne ml_ok
    sec
    rts
ml_ok:
    lda gs
    bne !+
    dec gs+1
!:  dec gs
    lda ge
    bne !+
    dec ge+1
!:  dec ge
    ldy #0
    lda (gs),y                  // the character moves from before the gap to after it
    sta (ge),y
    cmp #LF
    bne !+
    lda curline                 // crossed a line end: one line up
    bne ml_d
    dec curline+1
ml_d:
    dec curline
!:  clc
    rts

// move_right: cursor one character to the right. Carry set = already at the end of the text.
move_right:
    lda ge
    cmp #<SRC_LIMIT
    bne mr_ok
    lda ge+1
    cmp #>SRC_LIMIT
    bne mr_ok
    sec
    rts
mr_ok:
    ldy #0
    lda (ge),y                  // the character moves from after the gap to before it
    sta (gs),y
    inc gs
    bne !+
    inc gs+1
!:  inc ge
    bne !+
    inc ge+1
!:  cmp #LF
    bne !+
    inc curline
    bne !+
    inc curline+1
!:  clc
    rts

// peek_next: A = the character after the cursor (0 at the end of the text).
peek_next:
    lda ge
    cmp #<SRC_LIMIT
    bne pn_ok
    lda ge+1
    cmp #>SRC_LIMIT
    bne pn_ok
    lda #0
    rts
pn_ok:
    ldy #0
    lda (ge),y
    rts

// get_col: A = column of the cursor (characters since the start of its line; 255 at most).
get_col:
    lda gs
    sta tp
    lda gs+1
    sta tp+1
    ldx #0
gc1:
    lda tp
    cmp #<SRC_BASE
    bne gc2
    lda tp+1
    cmp #>SRC_BASE
    beq gc_done
gc2:
    lda tp
    bne !+
    dec tp+1
!:  dec tp
    ldy #0
    lda (tp),y
    cmp #LF
    beq gc_done
    inx
    bne gc1
gc_done:
    txa
    rts

// free_space: et2/et3 = number of free bytes in the gap.
free_space:
    sec
    lda ge
    sbc gs
    sta et2
    lda ge+1
    sbc gs+1
    sta et3
    rts

// ---- editing -----------------------------------------------------------------------------------------------------
// ed_insert: insert the ASCII character in A at the cursor. Carry set = no room (two bytes stay free).
ed_insert:
    sta et1
    jsr free_space
    lda et3
    bne ei_ok
    lda et2
    cmp #2
    bcc ei_full
ei_ok:
    ldy #0
    lda et1
    sta (gs),y
    inc gs
    bne !+
    inc gs+1
!:  lda et1
    cmp #LF
    bne !+
    inc curline
    bne !+
    inc curline+1
!:  lda #1
    sta modified
    clc
    rts
ei_full:
    sec
    rts

// ed_backspace: delete the character before the cursor.
ed_backspace:
    lda gs
    cmp #<SRC_BASE
    bne eb_ok
    lda gs+1
    cmp #>SRC_BASE
    bne eb_ok
    rts
eb_ok:
    lda gs
    bne !+
    dec gs+1
!:  dec gs
    ldy #0
    lda (gs),y
    cmp #LF
    bne !+
    lda curline
    bne eb_d
    dec curline+1
eb_d:
    dec curline
!:  lda #1
    sta modified
    rts

// ed_delete: delete the character under the cursor.
ed_delete:
    jsr peek_next
    beq edl_done
    inc ge
    bne !+
    inc ge+1
!:  lda #1
    sta modified
edl_done:
    rts

// ed_return: line feed plus the indentation of the current line (auto-indent).
ed_return:
    lda #LF
    jsr ed_insert
    bcs er_done
    lda gs                      // count the blanks at the start of the line we just left
    sta tp
    lda gs+1
    sta tp+1
    lda tp                      // tp = just before the line feed
    bne !+
    dec tp+1
!:  dec tp
    ldx #0                      // x = column of the end of that line... find its start first
er_back:
    lda tp
    cmp #<SRC_BASE
    bne er_b2
    lda tp+1
    cmp #>SRC_BASE
    beq er_start
er_b2:
    lda tp
    bne !+
    dec tp+1
!:  dec tp
    ldy #0
    lda (tp),y
    cmp #LF
    bne er_back
    inc tp                      // tp = first character of the line
    bne er_start
    inc tp+1
er_start:
    ldx #0
er_cnt:
    ldy #0
    lda (tp),y
    cmp #' '
    bne er_fill
    inx
    inc tp
    bne er_cnt
    inc tp+1
    jmp er_cnt
er_fill:
    cpx #0
    beq er_done
    stx et4
er_put:
    lda #' '
    jsr ed_insert
    bcs er_done
    dec et4
    bne er_put
er_done:
    rts

// ---- cursor movement ------------------------------------------------------------------------------------------
// cur_home: start of the line.   cur_end: end of the line.
cur_home:
    jsr get_col
    tax
    beq ch_done
ch1:
    jsr move_left
    dex
    bne ch1
ch_done:
    rts

cur_end:
    jsr peek_next
    beq cen_done
    cmp #LF
    beq cen_done
    jsr move_right
    jmp cur_end
cen_done:
    rts

// cur_up: one line up, keeping the column if the line above is long enough.
cur_up:
    lda curline
    cmp #1
    bne cu_go
    lda curline+1
    beq cu_done                 // already the first line
cu_go:
    jsr get_col
    sta et1                     // wanted column
    tax
    beq cu_atstart
cu1:
    jsr move_left
    dex
    bne cu1
cu_atstart:
    jsr move_left               // onto the end of the line above
    jsr get_col
    sta et2                     // its length
    cmp et1
    bcc cu_done                 // shorter than the wanted column: stay at its end
    sec
    sbc et1
    tax                         // move back by (length - wanted)
    beq cu_done
cu2:
    jsr move_left
    dex
    bne cu2
cu_done:
    rts

// cur_down: one line down.
cur_down:
    jsr get_col
    sta et1                     // wanted column
    ldx #0                      // find the end of the line, counting the characters passed
    stx et2
    stx et3
cd1:
    jsr peek_next
    beq cd_last                 // end of the text: there is no line below
    cmp #LF
    beq cd_found
    jsr move_right
    inc et2
    bne cd1
    inc et3
    jmp cd1
cd_last:
    lda et2                     // undo the movement
    ora et3
    beq cd_done
cd_undo:
    jsr move_left
    lda et2
    bne !+
    dec et3
!:  dec et2
    lda et2
    ora et3
    bne cd_undo
cd_done:
    rts
cd_found:
    jsr move_right              // over the line feed: start of the next line
    ldx et1                     // now move right up to the wanted column
    beq cd_done
cd2:
    jsr peek_next
    beq cd_done
    cmp #LF
    beq cd_done
    jsr move_right
    dex
    bne cd2
    rts

cur_top:                        // start of the text
    jsr move_left
    bcc cur_top
    rts

cur_bottom:                     // end of the text
    jsr move_right
    bcc cur_bottom
    rts

page_up:
    ldx #20
pgu1:
    stx et4
    jsr cur_up
    ldx et4
    dex
    bne pgu1
    rts

page_down:
    ldx #20
pgd1:
    stx et4
    jsr cur_down
    ldx et4
    dex
    bne pgd1
    rts

// goto_line: move the cursor to the start of line number et2/et3 (1 = first).
goto_line:
    jsr cur_top
gl1:
    lda curline
    cmp et2
    bne gl2
    lda curline+1
    cmp et3
    beq gl_done
gl2:
    jsr move_right
    bcs gl_done
    jmp gl1
gl_done:
    rts

// ---- drawing the text ------------------------------------------------------------------------------------------
// a2s: ASCII character in A -> screen code (lowercase character set).
a2s:
    cmp #$61
    bcc as1
    cmp #$7b
    bcs as1
    sec
    sbc #$60                    // a-z -> 1-26
    rts
as1:
    cmp #$41
    bcc as2
    cmp #$5b
    bcc as_ret                  // A-Z are the same (capital letters in this character set)
as2:
    cmp #$40
    bne as3
    lda #0                      // @
    rts
as3:
    cmp #$5b
    bne as4
    lda #$1b                    // [
    rts
as4:
    cmp #$5d
    bne as5
    lda #$1d                    // ]
    rts
as5:
    cmp #$7b
    bne as6
    lda #$9b                    // { shown as reversed [
    rts
as6:
    cmp #$7d
    bne as7
    lda #$9d                    // } shown as reversed ]
    rts
as7:
    cmp #$5c
    bne as8
    lda #$1c                    // backslash
    rts
as8:
    cmp #$5e
    bne as9
    lda #$1e                    // ^
    rts
as9:
    cmp #$5f
    bne as10
    lda #$64                    // underscore
    rts
as10:
    cmp #$7c
    bne as11
    lda #$5d                    // |
    rts
as11:
    cmp #$20
    bcs as_ret
    lda #$20                    // control characters (tab, ...) are shown as blanks
as_ret:
    rts

// rd_get: read the next character of the text from ep, skipping the gap. A = character, carry set at the
// end of the text. 'atcur' is set when the read position is the cursor.
rd_get:
    lda ep
    cmp gs
    bne rg1
    lda ep+1
    cmp gs+1
    bne rg1
    lda #1                      // this is the cursor position
    sta atcur
    lda ge                      // jump over the gap
    sta ep
    lda ge+1
    sta ep+1
rg1:
    lda ep+1
    cmp #>SRC_LIMIT
    bcc rg2
    bne rg_eof
    lda ep
    cmp #<SRC_LIMIT
    bcc rg2
rg_eof:
    sec
    rts
rg2:
    ldy #0
    lda (ep),y
    inc ep
    bne !+
    inc ep+1
!:  clc
    rts

// draw_line: draw the line that starts at ep into the screen row at scr (40 cells), consuming it
// including its line feed. Carry set if the end of the text was reached.
draw_line:
    lda #0
    sta et1                     // column within the line
    sta et2                     // x on the screen
dwl_next:
    jsr rd_get
    sta rch
    php
    lda atcur
    beq dwl_c1
    lda #0
    sta atcur
    jsr set_curcell
dwl_c1:
    plp
    bcs dwl_eof
    lda rch
    cmp #LF
    beq dwl_eol
    lda et1
    cmp leftcol
    bcc dwl_skip                 // left of the visible part
    ldx et2
    cpx #40
    bcs dwl_skip                 // right of the screen
    lda rch
    jsr a2s
    ldy et2
    sta (scr),y
    inc et2
dwl_skip:
    inc et1
    jmp dwl_next
dwl_eol:
    jsr fill_rest
    clc
    rts
dwl_eof:
    jsr fill_rest
    sec
    rts

fill_rest:                      // blank the cells from x = et2 to the end of the row
    ldy et2
    lda #$20
fr1:
    cpy #40
    bcs fr_done
    sta (scr),y
    iny
    bne fr1
fr_done:
    rts

// set_curcell: the cursor is at column et1 of the row at scr: remember its screen cell.
set_curcell:
    lda et1
    sec
    sbc leftcol
    bcc scc_hidden
    cmp #40
    bcs scc_hidden
    clc
    adc scr
    sta curcell
    lda scr+1
    adc #0
    sta curcell+1
    lda #1
    sta curvalid
    rts
scc_hidden:
    lda #0
    sta curvalid
    rts

// ensure_visible: scroll (topoff, leftcol) so that the cursor is on the screen.
ensure_visible:
    sec                         // cursor offset = gs - SRC_BASE
    lda gs
    sbc #<SRC_BASE
    sta et2
    lda gs+1
    sbc #>SRC_BASE
    sta et3
    lda et2                     // cursor before the first visible character: scroll up to its line start
    cmp topoff
    lda et3
    sbc topoff+1
    bcs ev_below
    jsr get_col                 // topoff = cursor offset - column
    sta et1
    sec
    lda et2
    sbc et1
    sta topoff
    lda et3
    sbc #0
    sta topoff+1
    jmp ev_horiz
ev_below:                       // count the lines between topoff and the cursor
ev_again:
    clc
    lda topoff
    adc #<SRC_BASE
    sta tp
    lda topoff+1
    adc #>SRC_BASE
    sta tp+1
    ldx #0                      // x = number of line feeds between
ev_scan:
    lda tp
    cmp gs
    bne ev_s2
    lda tp+1
    cmp gs+1
    beq ev_counted
ev_s2:
    ldy #0
    lda (tp),y
    cmp #LF
    bne !+
    inx
!:  inc tp
    bne ev_scan
    inc tp+1
    jmp ev_scan
ev_counted:
    cpx #TEXT_ROWS              // the cursor must be on one of rows 0 .. 23
    bcc ev_horiz
    clc                         // scroll one line down: topoff = after the first line feed from topoff
    lda topoff
    adc #<SRC_BASE
    sta tp
    lda topoff+1
    adc #>SRC_BASE
    sta tp+1
ev_nl:
    ldy #0
    lda (tp),y
    inc tp
    bne !+
    inc tp+1
!:  cmp #LF
    bne ev_nl
    sec
    lda tp
    sbc #<SRC_BASE
    sta topoff
    lda tp+1
    sbc #>SRC_BASE
    sta topoff+1
    jmp ev_again
ev_horiz:
    jsr get_col                 // horizontal scroll
    sta et1
    cmp leftcol
    bcs !+
    sta leftcol                 // left of the window
    rts
!:  sec
    lda et1
    sbc leftcol
    cmp #40
    bcc ev_done
    lda et1
    sec
    sbc #39
    sta leftcol                 // right of the window
ev_done:
    rts

// ed_redraw: scroll if necessary and draw the text rows and the status line.
ed_redraw:
    jsr ensure_visible
    clc                         // ep = address of the first visible character
    lda topoff
    adc #<SRC_BASE
    sta ep
    lda topoff+1
    adc #>SRC_BASE
    sta ep+1
    lda #<SCRN_BASE
    sta scr
    lda #>SCRN_BASE
    sta scr+1
    lda #0
    sta atcur
    sta curvalid
    lda #TEXT_ROWS
    sta rrows
rr1:
    jsr draw_line
    clc
    lda scr
    adc #40
    sta scr
    bcc !+
    inc scr+1
!:  dec rrows
    bne rr1
    lda curvalid                // show the cursor: reverse video of its cell
    beq rr_nocur
    lda curcell                 // (indirect addressing needs a zero page pointer)
    sta tp
    lda curcell+1
    sta tp+1
    ldy #0
    lda (tp),y
    eor #$80
    sta (tp),y
rr_nocur:
    jmp draw_status

// ---- status line -----------------------------------------------------------------------------------------------------
// put_str: write the 0-terminated ASCII string at address X:A to the screen at scr + y, advancing y
put_str:
    sta tp
    stx tp+1
    ldx #0
ps1:
    lda (tp,x)
    beq ps_done
    jsr a2s
    sta (scr),y
    iny
    inc tp
    bne ps1
    inc tp+1
    jmp ps1
ps_done:
    rts

// put_num: write the 16 bit number in et2/et3 as decimal digits at scr + y (no leading zeros).
put_num:
    lda #0
    sta et4                     // leading zero suppression: 0 until the first digit
    ldx #0
pn1:
    lda #'0'
    sta et1
pn2:
    lda et2                     // subtract the power of ten while possible
    sec
    sbc pow10_lo,x
    sta pnt
    lda et3
    sbc pow10_hi,x
    bcc pn_digit
    sta et3
    lda pnt
    sta et2
    inc et1
    jmp pn2
pn_digit:
    lda et1
    cmp #'0'
    bne pn_out
    lda et4
    bne pn_out
    cpx #4                      // the last digit is always written
    bne pn_next
pn_out:
    lda #1
    sta et4
    lda et1
    jsr a2s
    sta (scr),y
    iny
pn_next:
    inx
    cpx #5
    bne pn1
    rts

pow10_lo: .byte <10000, <1000, <100, <10, <1
pow10_hi: .byte >10000, >1000, >100, >10, >1

// draw_status: row 24: a message if there is one, else "Ln n Col n NAME free". Shown in reverse video.
draw_status:
    lda #<STATUS_ROW
    sta scr
    lda #>STATUS_ROW
    sta scr+1
    ldy #0
    lda #$20
ds_clr:
    sta (scr),y                 // blank the row
    iny
    cpy #40
    bne ds_clr
    ldy #0
    lda msgptr+1
    beq ds_normal
    lda msgptr
    ldx msgptr+1
    jsr put_str
    jmp ds_rev
ds_normal:
    lda #<m_ln
    ldx #>m_ln
    jsr put_str
    lda curline
    sta et2
    lda curline+1
    sta et3
    jsr put_num
    lda #<m_col
    ldx #>m_col
    jsr put_str
    sty ypos
    jsr get_col
    clc
    adc #1
    sta et2
    lda #0
    sta et3
    ldy ypos
    jsr put_num
    iny
    lda modified                // * after the name = changed since it was loaded / saved
    beq ds_name
    lda #'*'
    jsr a2s
    sta (scr),y
    iny
ds_name:
    lda namelen
    beq ds_free
    ldx #0
ds_n1:
    lda namebuf,x               // the file name is PETSCII (unshifted letters are $41-$5A)
    cmp #$41
    bcc ds_n2
    cmp #$5b
    bcs ds_n2
    ora #$20                    // -> ASCII lower case, shown as lower case
ds_n2:
    jsr a2s
    sta (scr),y
    iny
    inx
    cpx namelen
    bne ds_n1
ds_free:
    jsr free_space
    ldy #28                     // "nnnnn free" at the right
    jsr put_num
    lda #<m_free
    ldx #>m_free
    jsr put_str
ds_rev:
    ldy #0                      // reverse video
ds_r1:
    lda (scr),y
    ora #$80
    sta (scr),y
    iny
    cpy #40
    bne ds_r1
    rts

m_ln:   .text "Ln "
        .byte 0
m_col:  .text " Col "
        .byte 0
m_free: .text " free"
        .byte 0

// ---- editor variables ------------------------------------------------------------------------------------------------------------
topoff:    .word 0              // offset (from SRC_BASE) of the first character on the screen
leftcol:   .byte 0              // first visible column
curline:   .word 1              // line number of the cursor (1 = first)
modified:  .byte 0              // text changed since loaded / saved
atcur:     .byte 0
rch:       .byte 0
rrows:     .byte 0
pnt:       .byte 0
ypos:      .byte 0
curcell:   .word 0              // screen address of the cursor cell
curvalid:  .byte 0
msgptr:    .word 0              // message shown in the status line instead of the position (0 = none)
#if !HIROM                      // (on the Plus/4 the file name must be in the low RAM: the KERNAL reads it; see 64ide.asm)
namelen:   .byte 0              // current file name (PETSCII)
namebuf:   .fill 17, 0
#endif
