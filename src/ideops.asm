// This file is in the public domain: use it, change it, share it, sell it - do whatever you like with it.
// No permission, credit or payment needed. It comes as it is, with no warranty. Enjoy!
// Note: this has only been tested in the VICE emulator, never on real hardware.
// =====================================================================================
// ideops.asm - IDE commands: prompt line, load, save, autosave, compile and run
// =====================================================================================
//
// Messages are shown on the status line (row 24) through 'msgptr' until the next key. File names are
// kept in PETSCII (as typed: unshifted letters are $41-$5A, which is what the disk expects).

.macro SETMSG(m) {
    lda #<m
    sta msgptr
    lda #>m
    sta msgptr+1
}

// ---- prompt line -------------------------------------------------------------------------------------------
// pet2scr: PETSCII character in A -> screen code (for showing typed file names).
pet2scr:
    cmp #$c1
    bcc p2s1
    cmp #$db
    bcs p2s1
    and #$7f                    // shifted letters -> capitals
    rts
p2s1:
    cmp #$41
    bcc p2s2
    cmp #$5b
    bcs p2s2
    sec
    sbc #$40                    // unshifted letters -> lower case glyphs
p2s2:
    rts

// prompt: X:A = prompt text (ASCII). Lets the user type a line (at most 16 characters) into pbuf / plen.
// RETURN accepts (carry clear), RUN/STOP cancels (carry set).
prompt:
    sta ipr_msg
    stx ipr_msg+1
    lda #0
    sta plen
ipr_loop:
    lda #<STATUS_ROW
    sta scr
    lda #>STATUS_ROW
    sta scr+1
    ldy #0
    lda #$20
ipr_clr:
    sta (scr),y
    iny
    cpy #40
    bne ipr_clr
    ldy #0
    lda ipr_msg
    ldx ipr_msg+1
    jsr put_str
    sty ypos
    ldx #0
ipr_txt:
    cpx plen
    beq ipr_cur
    lda pbuf,x
    jsr pet2scr
    ldy ypos
    sta (scr),y
    inc ypos
    inx
    jmp ipr_txt
ipr_cur:
    ldy ypos
    lda #$a0                    // reversed blank: the cursor
    sta (scr),y
    jsr getkey
    cmp #$0d
    beq ipr_ok
    cmp #$03
    beq ipr_cancel
    cmp #$14
    beq ipr_del
    ldx plen
    cpx #16
    bcs ipr_loop                 // line full
    cmp #$20                    // accept letters, digits, punctuation
    bcc ipr_loop
    cmp #$60
    bcc ipr_store
    cmp #$c1
    bcc ipr_loop
    cmp #$db
    bcs ipr_loop
ipr_store:
    sta pbuf,x
    inc plen
    jmp ipr_loop
ipr_del:
    lda plen
    beq ipr_loop
    dec plen
    jmp ipr_loop
ipr_ok:
    clc
    rts
ipr_cancel:
    sec
    rts

// set_name: namebuf := pbuf (plus ".pas" if there is no extension).
set_name:
    ldx #0
sn1:
    lda pbuf,x
    sta namebuf,x
    inx
    cpx plen
    bne sn1
    stx namelen
    ldx #0                      // is there a '.' ?
sn2:
    lda namebuf,x
    cmp #'.'
    beq sn_done
    inx
    cpx namelen
    bne sn2
    lda namelen                 // no: append ".pas"
    cmp #13
    bcs sn_done
    tax
    lda #'.'
    sta namebuf,x
    lda #$50                    // p a s as typed (unshifted letters)
    sta namebuf+1,x
    lda #$41
    sta namebuf+2,x
    lda #$53
    sta namebuf+3,x
    txa
    clc
    adc #4
    sta namelen
sn_done:
    rts

// ---- messages from the drive ------------------------------------------------------------------------------------
// drive_message: show the drive's last error message (dc_buf, PETSCII) on the status line; "Drive not ready"
// if the drive did not answer.
drive_message:
    lda dc_len
    beq dm_none
    ldx #0
dm1:
    lda dc_buf,x
    jsr p2a
    sta msgbuf,x
    inx
    cpx dc_len
    bne dm1
    lda #0
    sta msgbuf,x
    SETMSG(msgbuf)
    rts
dm_none:
    SETMSG(m_nodrive)
    rts

// ---- file names for the drive ----------------------------------------------------------------------------------
// make_save_name: fnbuf := "@0:" + namebuf + ",S,W"
make_save_name:
    lda #'@'
    sta fnbuf
    lda #'0'
    sta fnbuf+1
    lda #':'
    sta fnbuf+2
    ldx #0
ms1:
    cpx namelen
    beq ms2
    lda namebuf,x
    sta fnbuf+3,x
    inx
    jmp ms1
ms2:
    lda #','
    sta fnbuf+3,x
    lda #'S'
    sta fnbuf+4,x
    lda #','
    sta fnbuf+5,x
    lda #'W'
    sta fnbuf+6,x
    txa
    clc
    adc #7
    sta fname_len
    lda #<fnbuf
    sta fname_ptr
    lda #>fnbuf
    sta fname_ptr+1
    rts

// make_auto_name: fnbuf := "@0:" + name up to the '.' + ".A" or ".B" (alternating) + ",S,W"
make_auto_name:
    lda #'@'
    sta fnbuf
    lda #'0'
    sta fnbuf+1
    lda #':'
    sta fnbuf+2
    ldx #0
    lda namelen
    bne ma1
    ldy #0                      // no name yet: "untitled"
ma0:
    lda m_untitled,y
    beq ma2
    sta fnbuf+3,x
    inx
    iny
    jmp ma0
ma1:
    cpx namelen
    beq ma2
    lda namebuf,x
    cmp #'.'
    beq ma2
    sta fnbuf+3,x
    inx
    jmp ma1
ma2:
    lda #'.'
    sta fnbuf+3,x
    lda as_toggle               // alternate between NAME.A and NAME.B
    eor #1
    sta as_toggle
    clc
    adc #$41
    sta fnbuf+4,x
    lda #','
    sta fnbuf+5,x
    lda #'S'
    sta fnbuf+6,x
    lda #','
    sta fnbuf+7,x
    lda #'W'
    sta fnbuf+8,x
    txa
    clc
    adc #9
    sta fname_len
    lda #<fnbuf
    sta fname_ptr
    lda #>fnbuf
    sta fname_ptr+1
    rts

// ---- save ------------------------------------------------------------------------------------------------------------
// save_file: save the text under the current name (asks for one if there is none). Carry set = failed.
save_file:
    lda namelen
    bne sf_have
    lda #<pm_save
    ldx #>pm_save
    jsr prompt
    bcs sf_cancel
    lda plen
    beq sf_cancel
    jsr set_name
sf_have:
    jsr make_save_name
    lda #0
    sta dc_len
    lda #1
    sta dc_quiet
    jsr save_text
    bcs sf_fail
    jsr drive_check
    bcs sf_fail
    lda #0
    sta modified
    SETMSG(m_saved)
    clc
    rts
sf_fail:
    jsr drive_check             // fetch the drive's message
    jsr drive_message
sf_cancel:
    sec
    rts

// autosave: write the text to NAME.A / NAME.B (alternating). Carry set = failed.
autosave:
    jsr make_auto_name
    lda #0
    sta dc_len
    lda #1
    sta dc_quiet
    jsr save_text
    bcs as_fail
    jsr drive_check
    rts
as_fail:
    jsr drive_check
    sec
    rts

// ---- load ------------------------------------------------------------------------------------------------------------
// show_dir: list the .pas files on the disk over the screen; any key returns.
show_dir:
    lda #147
    jsr KF_CHROUT
    lda #1
    sta dc_quiet
    jsr list_pas
    lda #13
    jsr KF_CHROUT
    lda #<m_anykey
    ldx #>m_anykey
    jsr KF_puts
    jmp getkey

load_file:
lf_ask:
    lda #<pm_load
    ldx #>pm_load
    jsr prompt
    bcc lf_got
    rts                         // cancelled
lf_got:
    lda plen
    bne lf_go
    jsr show_dir                // empty name: show the Pascal files, then ask again
    jmp lf_ask
lf_go:
    jsr set_name
    lda #<namebuf
    sta fname_ptr
    lda #>namebuf
    sta fname_ptr+1
    lda namelen
    sta fname_len
    lda #0
    sta dc_len
    sta ls_any
    lda #1
    sta dc_quiet
    jsr load_source
    bcs lf_fail
    jsr drive_check
    bcs lf_fail
    lda src_end                 // the text is in the buffer: put the gap behind it
    sta gs
    lda src_end+1
    sta gs+1
    lda #<SRC_LIMIT
    sta ge
    lda #>SRC_LIMIT
    sta ge+1
    lda #1                      // curline = 1 + number of line feeds
    sta curline
    lda #0
    sta curline+1
    lda #<SRC_BASE
    sta tp
    lda #>SRC_BASE
    sta tp+1
lf_cnt:
    lda tp
    cmp gs
    bne lf_c1
    lda tp+1
    cmp gs+1
    beq lf_counted
lf_c1:
    ldy #0
    lda (tp),y
    cmp #LF
    bne lf_c2
    inc curline
    bne lf_c2
    inc curline+1
lf_c2:
    inc tp
    bne lf_cnt
    inc tp+1
    jmp lf_cnt
lf_counted:
    jsr cur_top                 // cursor to the start of the text
    lda #0
    sta topoff
    sta topoff+1
    sta leftcol
    sta modified
    SETMSG(m_loaded)
    rts
lf_fail:
    pha
    lda ls_any                  // a failed load may have overwritten the old text: start empty
    beq lf_keep
    jsr ed_new
    lda #0
    sta namelen
lf_keep:
    pla
    cmp #1
    bne lf_drive
    SETMSG(m_toolong)
    rts
lf_drive:
    jsr drive_check
    jmp drive_message

#if !EDONLY
// ---- compile and run -----------------------------------------------------------------------------------------------------
// run_text: compile the text; on an error put the cursor on the line and show the message, else run the
// program and return to the editor when a key is pressed (or, in disk mode, write it to disk as a standalone
// program named like the source without ".pas"). A bit 0 = autosave first, bit 1 = compile to disk.
run_text:
    sta rt_mode
    SETMSG(m_working)
    jsr draw_status
    lda rt_mode
    and #2
    beq rt_named
    lda namelen                 // compile to disk needs a name: ask for one if the text has none yet
    bne rt_named
    lda #<pm_save
    ldx #>pm_save
    jsr prompt
    bcs rt_cancel
    lda plen
    beq rt_cancel
    jsr set_name
rt_named:
    lda rt_mode
    and #1
    beq rt_nosave
    jsr autosave                // the text is safe before anything is run
    bcc rt_nosave
    SETMSG(m_nosave)
    rts
rt_cancel:
    lda #0
    sta msgptr+1
    rts
rt_nosave:
    sec                         // remember the cursor offset
    lda gs
    sbc #<SRC_BASE
    sta cursoff
    lda gs+1
    sbc #>SRC_BASE
    sta cursoff+1
    jsr cur_bottom              // the gap to the end: the text is one piece
    ldy #0
    tya
    sta (gs),y                  // zero terminator for the compiler
#if HIROM
    lda rt_mode                 // Plus/4: a program that is run goes to the low RAM (it runs with the ROMs on), a program
    and #2                      // that is written to disk is built behind the text (the RAM under the ROMs)
    bne rt_buf
    lda #<CODE_BASE
    sta codebase
    lda #>CODE_BASE
    sta codebase+1
    lda #<CODE_LIMIT
    sta codelimit
    lda #>CODE_LIMIT
    sta codelimit+1
    jmp rt_lim2
rt_buf:
    lda gs
    clc
    adc #1
    lda gs+1
    adc #1
    sta codebase+1
    lda #0
    sta codebase
    lda #<BUF_LIMIT
    sta codelimit
    lda #>BUF_LIMIT
    sta codelimit+1
    jmp rt_lim2
#else
    lda gs                      // the generated code goes behind the text, on the next page
    clc
    adc #1
    lda gs+1
    adc #1
    sta codebase+1
    lda #0
    sta codebase
    lda rt_mode                 // to run in memory the code must stay below the program's data; a program that
    and #2                      // is written to disk is only built in the buffer, so it may use all memory up to
    beq rt_lim                  // the software stack
    lda #<STK_TOP
    sta codelimit
    lda #>STK_TOP
    sta codelimit+1
    jmp rt_lim2
rt_lim:
    lda #<CODE_LIMIT
    sta codelimit
    lda #>CODE_LIMIT
    sta codelimit+1
#endif
rt_lim2:
    lda codebase+1
    clc
    adc #1
    cmp codelimit+1             // not even a page of room left
    bcc rt_room
    jsr back_to_cursor
    SETMSG(m_nocode)
    rts
rt_room:
    lda gs                      // the compiler uses the zero page: keep the gap pointers in RAM
    sta sav_gs
    lda gs+1
    sta sav_gs+1
    lda ge
    sta sav_ge
    lda ge+1
    sta sav_ge+1
    lda rt_mode                 // cmode 1 = build a standalone program image
    lsr
    and #1
    sta cmode
    lda #<SRC_BASE
    sta src
    lda #>SRC_BASE
    sta src+1
    jsr compile
    php
    lda #0
    sta cmode
    lda errcode
    sta r_err
    lda line
    sta r_line
    lda line+1
    sta r_line+1
    lda cout                    // the end of the generated code (the editor's 'ge' shares this zero page cell)
    sta r_cout
    lda cout+1
    sta r_cout+1
    jsr restore_gap
    plp
    bcc rt_compiled
    jmp rt_error
rt_compiled:
    lda rt_mode
    and #2
    beq rt_run
    jmp rt_todisk
rt_run:
#if HIROM
    lda rtused+1                // Plus/4: the extension chunks (real, pointers, write(x:w), Random) have no room next to the
    and #$0e                    // editor: such a program can only run as a file (CTRL+C), it is not run in place
    beq rt_inplace_ok
    jsr back_to_cursor
    SETMSG(m_needdisk)
    rts
rt_inplace_ok:
#endif
    lda #147                    // run the program on a clear screen
    jsr KF_CHROUT
    jsr KF_run_program
    lda #13
    jsr KF_CHROUT
    lda #<m_anykey
    ldx #>m_anykey
    jsr KF_puts
    jsr getkey
    jsr restore_gap
    jsr ide_colors
    lda #0
    sta msgptr+1                // the "Compiling..." message is obsolete
    jmp back_to_cursor
rt_todisk:                      // write the program image (in the code buffer) to disk
    lda r_cout
    sta cout
    lda r_cout+1
    sta cout+1
    jsr make_prg_name
    jsr save_prg
    bcs rd_fail
    lda #0
    sta dc_len
    lda #1
    sta dc_quiet
    jsr drive_check
    bcs rd_fail
    SETMSG(m_prgsaved)
    jmp back_to_cursor
rd_fail:
    lda #1
    sta dc_quiet
    jsr drive_check
    jsr back_to_cursor
    jmp drive_message
rt_error:
    jsr back_to_cursor
    lda r_line
    sta et2
    lda r_line+1
    sta et3
    jsr goto_line
    lda r_err                   // message: "Error: <text>"
    jsr get_errmsg
    sta tp
    stx tp+1
    ldx #0
rte1:
    lda m_error,x
    beq rte2
    sta msgbuf,x
    inx
    jmp rte1
rte2:
    ldy #0
rte3:
    lda (tp),y
    sta msgbuf,x
    beq rte4
    inx
    iny
    jmp rte3
rte4:
    SETMSG(msgbuf)
    rts

// make_prg_name: fname_ptr / fname_len = "@0:" + the name of the text up to its first '.' + ",P,W" (PETSCII)
make_prg_name:
    ldx #0
mp1:
    cpx namelen
    beq mp2
    lda namebuf,x
    cmp #'.'
    beq mp2
    sta prg_name+3,x
    inx
    jmp mp1
mp2:
    ldy #0
mp3:
    lda prg_tail,y
    sta prg_name+3,x
    inx
    iny
    cpy #4
    bne mp3
    txa
    clc
    adc #3
    sta fname_len
    lda #<prg_name
    sta fname_ptr
    lda #>prg_name
    sta fname_ptr+1
    rts
#if !HIROM                      // (Plus/4: in the low RAM, see 64ide.asm - the KERNAL reads the file name)
prg_name: .byte $40, $30, $3a   // "@0:" (replace an existing file)
          .fill 24, 0
#endif
prg_tail: .byte $2c, $50, $2c, $57      // ",P,W"
rt_mode:  .byte 0               // bit 0 = autosave first, bit 1 = compile to disk

#endif

restore_gap:                    // gap pointers back from RAM (the compile or the program used the zero page)
    lda sav_gs
    sta gs
    lda sav_gs+1
    sta gs+1
    lda sav_ge
    sta ge
    lda sav_ge+1
    sta ge+1
    rts

back_to_cursor:                 // move the gap back to the cursor offset remembered by run_text
btc:
    sec
    lda gs
    sbc #<SRC_BASE
    tax
    lda gs+1
    sbc #>SRC_BASE
    cmp cursoff+1
    bne btc_mv
    cpx cursoff
    beq btc_done
btc_mv:
    jsr move_left
    bcc btc
btc_done:
    rts

// (the check of the editor alone, syntax.asm, uses the two routines above as well)



// compile_progress: called by the lexer for every line feed: show the number of the line being compiled on the status
// line, right of "Compiling..." (reverse video, written straight to the screen). Keeps A, X and Y.
compile_progress:
    pha
    txa
    pha
    tya
    pha
    lda line
    sta pg_v
    lda line+1
    sta pg_v+1
    lda #0
    sta pg_nz
    ldx #0
pg_next:
    lda #$30
    sta pg_d
pg_sub:
    lda pg_v
    sec
    sbc pg_pow_lo,x
    sta pg_t
    lda pg_v+1
    sbc pg_pow_hi,x
    bcc pg_done
    sta pg_v+1
    lda pg_t
    sta pg_v
    inc pg_d
    jmp pg_sub
pg_done:
    lda pg_d
    cmp #$30
    bne pg_emit
    cpx #4                      // the last digit is always shown
    beq pg_emit
    lda pg_nz
    bne pg_emit
    lda #$a0                    // leading zero: a blank (reverse)
    jmp pg_put
pg_emit:
    inc pg_nz
    lda pg_d
    ora #$80
pg_put:
    sta STATUS_ROW+13,x
    inx
    cpx #5
    bne pg_next
    pla
    tay
    pla
    tax
    pla
    rts
pg_pow_lo: .byte <10000, <1000, <100, <10, <1
pg_pow_hi: .byte >10000, >1000, >100, >10, >1
pg_v:  .word 0
pg_t:  .byte 0
pg_d:  .byte 0
pg_nz: .byte 0

// ---- data ---------------------------------------------------------------------------------------------------------------------
pm_load:     .text "Load: "
             .byte 0
pm_save:     .text "Save as: "
             .byte 0
m_saved:     .text "Saved"
             .byte 0
m_loaded:    .text "Loaded"
             .byte 0
m_toolong:   .text "File too long for the buffer"
             .byte 0
m_nodrive:   .text "Drive not ready"
             .byte 0
#if !EDONLY
m_working:   .text "Compiling..."
             .byte 0
m_prgsaved:  .text "Program saved"
             .byte 0
m_nosave:    .text "Autosave failed (F6 runs without)"
             .byte 0
m_nocode:    .text "Text too long: no room for the code"
             .byte 0
#if HIROM
m_needdisk:  .text "Uses real/pointers/:w: compile to disk"
             .byte 0
#endif
m_error:     .text "Error: "
             .byte 0
#endif
m_untitled:  .text "UNTITLED"
             .byte 0
#if !HIROM                      // (Plus/4: in the low RAM, see 64ide.asm - puts runs with the ROMs on and reads it)
m_anykey:    .text "-- press a key --"
             .byte 0
#endif
as_toggle:   .byte 0
plen:        .byte 0
ipr_msg:      .word 0
pbuf:        .fill 17, 0
#if !HIROM
fnbuf:       .fill 28, 0
#endif
msgbuf:      .fill 48, 0
cursoff:     .word 0
sav_gs:      .word 0
sav_ge:      .word 0
r_err:       .byte 0
r_line:      .word 0
r_cout:      .word 0
